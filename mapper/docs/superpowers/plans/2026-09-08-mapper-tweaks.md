# mapper text size and building zoom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two steppers to mapper's style control that scale every label in the
current style and raise the zoom at which buildings start drawing, remembered
across launches.

**Architecture:** A new pure module `src/tweaks.js` holds the notch tables, the
`localStorage` validation, and `applyTweaks(style, tweaks)`, a non-mutating
style transform. `src/tweaks.jsx` renders the two stepper rows and owns the
`tweaks` signal. `src/styles.jsx` keeps the style as fetched and re-applies the
transform to that held object on every stepper move and every style switch.
`src/main.jsx` stops handing MapLibre a style URL at startup and instead
fetches the JSON, transforms it, and constructs the map from the object.

**Tech Stack:** Preact + `@preact/signals`, MapLibre GL JS 5, esbuild (`jsx:
automatic`, `jsxImportSource: preact`), `node --test` for pure modules,
Playwright for the browser specs.

## Global Constraints

- Text notches, exactly: `1, 1.1, 1.2, 1.3, 1.4, 1.5`. Displayed as
  `100%`…`150%`.
- Buildings notches, exactly: `13, 14, 15, 16`. Displayed as the bare number.
- Both default to the low end: `{ textScale: 1, buildingMinZoom: 13 }`.
- Storage key: `mapper.tweaks`, alongside `mapper.view`, `mapper.places`,
  `mapper.style`.
- A value that is not one of the listed notches, a missing field, or a
  malformed document falls back to the defaults.
- `applyTweaks` must not mutate its input. mapper re-transforms the same held
  object on every change, so a mutating transform would compound scale on
  scale.
- A building layer is one whose `source-layer` is `building`. Nothing keys off
  layer ids.
- The buildings notch is a floor: raise `minzoom` to it, and drop any building
  layer whose `maxzoom` is at or below it.
- A `text-size` that is neither a plain number nor a flat
  `["interpolate", ["linear"], ["zoom"], z1, s1, ...]` is left alone, not
  guessed at.
- Pure modules take a `localStorage`-shaped store as an argument so they run
  under `node --test` without a browser, the same shape as `view.js`,
  `places.js` and `styles.js`.
- Repo conventions: two-space indent, no semicolons, single quotes, comments
  only where they say *why*.
- Full gate: `npm test` (`node --test test/*.test.js && playwright test`), run
  from `/home/john/src/wider/mapper`.

---

### Task 1: The pure tweaks module

**Files:**
- Create: `src/tweaks.js`
- Test: `test/tweaks.test.js`

**Model:** `sonnet` — the transform's edge cases need judgment, not transcription.

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `TWEAKS_KEY: string` (`'mapper.tweaks'`)
  - `TEXT_SCALES: number[]`, `BUILDING_ZOOMS: number[]`
  - `DEFAULT_TWEAKS: { textScale: number, buildingMinZoom: number }`
  - `validateTweaks(value: unknown): {textScale, buildingMinZoom} | null`
  - `parseTweaks(raw: string | null): {textScale, buildingMinZoom}`
  - `loadTweaks(store): {textScale, buildingMinZoom}`
  - `saveTweaks(store, tweaks): {textScale, buildingMinZoom} | null`
  - `applyTweaks(style: object, tweaks: object): object`

- [ ] **Step 1: Write the failing test**

Create `test/tweaks.test.js`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  TWEAKS_KEY, TEXT_SCALES, BUILDING_ZOOMS, DEFAULT_TWEAKS,
  validateTweaks, parseTweaks, loadTweaks, saveTweaks, applyTweaks,
} from '../src/tweaks.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    raw: map,
  }
}

const BIG = { textScale: 1.5, buildingMinZoom: 15 }

function stub() {
  return {
    version: 8,
    name: 'stub',
    sources: {},
    layers: [
      { id: 'bg', type: 'background', paint: { 'background-color': '#fff' } },
      {
        id: 'plain-label',
        type: 'symbol',
        'source-layer': 'place',
        layout: { 'text-size': 12 },
      },
      {
        id: 'interp-label',
        type: 'symbol',
        'source-layer': 'place',
        layout: { 'text-size': ['interpolate', ['linear'], ['zoom'], 10, 10, 16, 20] },
      },
      { id: 'icon-only', type: 'symbol', 'source-layer': 'poi', layout: { 'icon-size': 1 } },
      { id: 'odd-label', type: 'symbol', 'source-layer': 'place', layout: { 'text-size': ['get', 'size'] } },
      { id: 'building', type: 'fill', 'source-layer': 'building', minzoom: 13, maxzoom: 14 },
      { id: 'building-3d', type: 'fill-extrusion', 'source-layer': 'building', minzoom: 14 },
      { id: 'road', type: 'line', 'source-layer': 'transportation', minzoom: 4 },
    ],
  }
}

const layer = (style, id) => style.layers.find((l) => l.id === id)

test('the notches and defaults are the listed ones', () => {
  assert.deepEqual(TEXT_SCALES, [1, 1.1, 1.2, 1.3, 1.4, 1.5])
  assert.deepEqual(BUILDING_ZOOMS, [13, 14, 15, 16])
  assert.deepEqual(DEFAULT_TWEAKS, { textScale: 1, buildingMinZoom: 13 })
  assert.deepEqual(validateTweaks(DEFAULT_TWEAKS), DEFAULT_TWEAKS)
})

test('a saved tweaks value round-trips', () => {
  const store = fakeStore()
  assert.deepEqual(saveTweaks(store, BIG), BIG)
  assert.deepEqual(loadTweaks(store), BIG)
  assert.equal(store.raw.size, 1)
  assert.ok(store.raw.has(TWEAKS_KEY))
})

test('a missing key gives the default tweaks', () => {
  assert.deepEqual(loadTweaks(fakeStore()), DEFAULT_TWEAKS)
})

test('a malformed document gives the default tweaks', () => {
  assert.deepEqual(loadTweaks(fakeStore({ [TWEAKS_KEY]: '{not json' })), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks('[]'), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks('null'), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks(null), DEFAULT_TWEAKS)
})

test('an off-notch value or a missing field gives the default tweaks', () => {
  assert.deepEqual(parseTweaks(JSON.stringify({ textScale: 1.25, buildingMinZoom: 15 })), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks(JSON.stringify({ textScale: 1.2, buildingMinZoom: 12 })), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks(JSON.stringify({ textScale: 1.2 })), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks(JSON.stringify({ textScale: '1.2', buildingMinZoom: 15 })), DEFAULT_TWEAKS)
  assert.equal(validateTweaks(null), null)
  assert.equal(validateTweaks(7), null)
})

test('saving an off-notch value writes nothing', () => {
  const store = fakeStore()
  assert.equal(saveTweaks(store, { textScale: 2, buildingMinZoom: 13 }), null)
  assert.equal(store.raw.size, 0)
})

test('a plain text-size scales', () => {
  const out = applyTweaks(stub(), BIG)
  assert.equal(layer(out, 'plain-label').layout['text-size'], 18)
})

test("an interpolate's outputs scale and its zoom stops do not", () => {
  const out = applyTweaks(stub(), BIG)
  assert.deepEqual(layer(out, 'interp-label').layout['text-size'],
    ['interpolate', ['linear'], ['zoom'], 10, 15, 16, 30])
})

test('an absent or unrecognised text-size is left alone', () => {
  const out = applyTweaks(stub(), BIG)
  assert.deepEqual(layer(out, 'icon-only'), layer(stub(), 'icon-only'))
  assert.deepEqual(layer(out, 'odd-label').layout['text-size'], ['get', 'size'])
})

test("a building layer's minzoom rises to the floor", () => {
  const out = applyTweaks(stub(), { textScale: 1, buildingMinZoom: 15 })
  assert.equal(layer(out, 'building-3d').minzoom, 15)
})

test('a building layer whose maxzoom is at or below the floor is dropped', () => {
  const out = applyTweaks(stub(), { textScale: 1, buildingMinZoom: 15 })
  assert.equal(layer(out, 'building'), undefined)
  const at = applyTweaks(stub(), { textScale: 1, buildingMinZoom: 14 })
  assert.equal(layer(at, 'building'), undefined)
})

test('a non-building layer is untouched by the floor', () => {
  const out = applyTweaks(stub(), { textScale: 1, buildingMinZoom: 16 })
  assert.deepEqual(layer(out, 'road'), layer(stub(), 'road'))
})

test('the default tweaks leave a style alone', () => {
  assert.deepEqual(applyTweaks(stub(), DEFAULT_TWEAKS), stub())
})

test('the input style is not mutated', () => {
  const input = stub()
  const before = JSON.stringify(input)
  const out = applyTweaks(input, BIG)
  assert.equal(JSON.stringify(input), before)
  assert.notEqual(out, input)
  assert.notEqual(out.layers, input.layers)
})

test('applying twice to the same input does not compound', () => {
  const input = stub()
  const once = applyTweaks(input, BIG)
  const twice = applyTweaks(input, BIG)
  assert.deepEqual(twice, once)
})

test('off-notch tweaks fall back to the defaults inside the transform', () => {
  assert.deepEqual(applyTweaks(stub(), { textScale: 3, buildingMinZoom: 20 }), stub())
  assert.deepEqual(applyTweaks(stub(), null), stub())
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/john/src/wider/mapper && node --test test/tweaks.test.js`
Expected: FAIL, `Cannot find module '.../src/tweaks.js'`.

- [ ] **Step 3: Write the implementation**

Create `src/tweaks.js`:

```js
export const TWEAKS_KEY = 'mapper.tweaks'

export const TEXT_SCALES = [1, 1.1, 1.2, 1.3, 1.4, 1.5]
export const BUILDING_ZOOMS = [13, 14, 15, 16]

export const DEFAULT_TWEAKS = { textScale: TEXT_SCALES[0], buildingMinZoom: BUILDING_ZOOMS[0] }

export function validateTweaks(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const { textScale, buildingMinZoom } = value
  if (!TEXT_SCALES.includes(textScale)) return null
  if (!BUILDING_ZOOMS.includes(buildingMinZoom)) return null
  return { textScale, buildingMinZoom }
}

export function parseTweaks(raw) {
  if (typeof raw !== 'string') return DEFAULT_TWEAKS
  let value
  try {
    value = JSON.parse(raw)
  } catch {
    return DEFAULT_TWEAKS
  }
  return validateTweaks(value) || DEFAULT_TWEAKS
}

export function loadTweaks(store) {
  return parseTweaks(store.getItem(TWEAKS_KEY))
}

export function saveTweaks(store, tweaks) {
  const clean = validateTweaks(tweaks)
  if (clean) store.setItem(TWEAKS_KEY, JSON.stringify(clean))
  return clean
}

// In a flat ["interpolate", ["linear"], ["zoom"], z1, s1, z2, s2, ...] the
// outputs sit at the even indexes from 4 up and the zoom stops at the odd ones.
// No style nests an expression under an output, so anything else is left alone.
function scaleTextSize(size, scale) {
  if (typeof size === 'number') return size * scale
  if (!Array.isArray(size) || size[0] !== 'interpolate' || size.length < 5) return size
  const out = size.slice()
  for (let i = 4; i < out.length; i += 2) {
    if (typeof out[i] !== 'number') return size
    out[i] = out[i] * scale
  }
  return out
}

function scaleLayer(layer, scale) {
  if (scale === 1) return layer
  if (layer.type !== 'symbol' || !layer.layout) return layer
  const size = scaleTextSize(layer.layout['text-size'], scale)
  if (size === layer.layout['text-size']) return layer
  return { ...layer, layout: { ...layer.layout, 'text-size': size } }
}

// Returns a new style. mapper re-transforms the style it holds as fetched on
// every change, so mutating the input would compound scale on scale.
export function applyTweaks(style, tweaks) {
  const { textScale, buildingMinZoom } = validateTweaks(tweaks) || DEFAULT_TWEAKS
  if (!style || !Array.isArray(style.layers)) return style
  const layers = []
  for (const layer of style.layers) {
    if (layer['source-layer'] !== 'building') {
      layers.push(scaleLayer(layer, textScale))
      continue
    }
    if (typeof layer.maxzoom === 'number' && layer.maxzoom <= buildingMinZoom) continue
    const minzoom = Math.max(buildingMinZoom, typeof layer.minzoom === 'number' ? layer.minzoom : 0)
    layers.push(minzoom === layer.minzoom ? layer : { ...layer, minzoom })
  }
  return { ...style, layers }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd /home/john/src/wider/mapper && node --test test/tweaks.test.js`
Expected: PASS, all tests, 0 failures.

- [ ] **Step 5: Run the whole node suite for regressions**

Run: `cd /home/john/src/wider/mapper && node --test test/*.test.js`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd /home/john/src/wider/mapper
git add src/tweaks.js test/tweaks.test.js
git commit -m "Add the tweaks module: notches, storage, and the style transform"
```

---

### Task 2: Fetch and transform the startup style

**Files:**
- Modify: `src/main.jsx` (whole `start()` body)
- Modify: `src/styles.jsx:23-53` (`switchStyle`), `:74-91` (`addStyleControl`)
- Modify: `test/harness.js:23-48` (the stub style and its routing)
- Test: `test/map.spec.js` (one added spec)

**Model:** `sonnet` — coordinated changes across four files, and the harness
change has to keep fifteen existing specs green.

**Interfaces:**
- Consumes: `applyTweaks`, `loadTweaks`, `DEFAULT_TWEAKS` from `src/tweaks.js`
  (Task 1).
- Produces:
  - `addStyleControl(map, store, style)` — third argument is the style as
    fetched, untransformed.
  - `styleFor(id)` in `test/harness.js` now returns a style with the layers
    `bg`, `place-label` (numeric `text-size` 12), `poi-label` (interpolate),
    and `building` (fill, `source-layer: building`, `minzoom: 13`), on which
    Task 3's specs assert.

- [ ] **Step 1: Extend the Playwright stub style**

The stub currently has one background layer and no sources, so nothing in it
can show the transform. Replace `styleFor` in `test/harness.js` (lines 31-38)
with:

```js
// The symbol layers sit on an empty inline GeoJSON source and carry no
// text-field, so neither tiles nor glyphs are ever fetched for them. The
// building layer needs a vector source to carry a source-layer; its tiles are
// declared inline so no TileJSON is fetched, and at the default view its
// minzoom keeps the source from being asked for anything.
export function styleFor(id) {
  return {
    version: 8,
    name: id,
    sources: {
      empty: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
      vector: { type: 'vector', tiles: ['https://tiles.openfreemap.org/data/{z}/{x}/{y}.pbf'] },
    },
    layers: [
      { id: 'bg', type: 'background', paint: { 'background-color': STYLE_COLORS[id] || '#cfe8cf' } },
      { id: 'place-label', type: 'symbol', source: 'empty', layout: { 'text-size': 12 } },
      {
        id: 'poi-label',
        type: 'symbol',
        source: 'empty',
        layout: { 'text-size': ['interpolate', ['linear'], ['zoom'], 10, 10, 16, 20] },
      },
      {
        id: 'building',
        type: 'fill',
        source: 'vector',
        'source-layer': 'building',
        minzoom: 13,
        paint: { 'fill-color': '#ddd' },
      },
    ],
  }
}
```

- [ ] **Step 2: Abort the tile path in the shared route**

In `test/harness.js`, add the tile abort to `routeStyle` so no vector tile
request leaves the machine, the way the existing failed-tile spec already
does. Replace the body of `routeStyle` (lines 42-48) with:

```js
export async function routeStyle(page) {
  await page.route('**/tiles.openfreemap.org/data/**', (r) => r.abort('failed'))
  await page.route('**/tiles.openfreemap.org/**', (r) => {
    const id = new URL(r.request().url()).pathname.split('/').pop()
    const body = STYLE_COLORS[id] ? styleFor(id) : STYLE
    return r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) })
  })
}
```

- [ ] **Step 3: Run the existing Playwright suite against the new stub**

Run: `cd /home/john/src/wider/mapper && npx playwright test`
Expected: PASS, all existing specs. The suite still passes against the
unchanged `main.jsx`, because the stub is still fetched by URL and MapLibre
accepts it as-is.

If `open()` now times out on `window.mapper.map.loaded()`, the vector source
is being asked for a tile the abort route kills. Fix it by fulfilling instead
of aborting — `r.fulfill({ status: 200, contentType: 'application/x-protobuf', body: '' })`
— and note the change in the commit message. Do not change `open()`.

- [ ] **Step 4: Hold the fetched style in `styles.jsx`**

In `src/styles.jsx`, add the imports below the existing `styles.js` import:

```js
import { loadTweaks, applyTweaks } from './tweaks.js'
import { tweaks } from './tweaks.jsx'
```

Task 3 creates `src/tweaks.jsx`. Create it now as a two-line stub so this task
builds; Task 3 fills it in:

```jsx
import { signal } from '@preact/signals'
import { DEFAULT_TWEAKS } from './tweaks.js'

export const tweaks = signal(DEFAULT_TWEAKS)
```

Add the module-level holder beside the existing `let timer = 0`:

```js
// The style as fetched, untransformed. A stepper move re-transforms this same
// object rather than refetching, so the transform must not mutate it.
let fetched = null
```

In `switchStyle`, replace `map.setStyle(style)` (line 39) with:

```js
  fetched = style
  // Read at apply time, not at click time, so a stepper moved while this
  // switch is in flight is carried by the switch when it lands.
  map.setStyle(applyTweaks(style, tweaks.value))
```

Change `addStyleControl` to take and hold the fetched style. Replace its first
two lines (74-75) with:

```js
export function addStyleControl(map, store, style) {
  current.value = loadStyle(store)
  tweaks.value = loadTweaks(store)
  fetched = style
```

- [ ] **Step 5: Fetch and transform the startup style in `main.jsx`**

Replace the whole of `src/main.jsx` with:

```jsx
import { createMap } from './map.js'
import { loadView, saveView } from './view.js'
import { loadStyle, styleUrl } from './styles.js'
import { loadTweaks, applyTweaks } from './tweaks.js'
import { addStyleControl } from './styles.jsx'
import { render } from 'preact'
import { Places, attach } from './places.jsx'
import { store } from './store.js'

const NO_WEBGL = 'This window cannot draw the map: WebGL is unavailable.'
const LOAD_FAILED = 'This window cannot draw the map: the map style failed to load.'

const SAVE_DELAY = 300

// MapLibre's transformStyle hook exists only on setStyle, not on the map
// constructor, so a style loaded by URL at startup cannot be transformed on the
// way in. Fetching it here is the only way to hand the constructor an object.
async function fetchStyle(id) {
  const res = await fetch(styleUrl(id))
  if (!res.ok) throw new Error('HTTP ' + res.status)
  return res.json()
}

async function start() {
  const container = document.getElementById('map')

  let style
  try {
    style = await fetchStyle(loadStyle(store))
  } catch (err) {
    container.textContent = LOAD_FAILED
    console.error(err)
    return
  }

  let map
  try {
    map = createMap(container, loadView(store), applyTweaks(style, loadTweaks(store)))
  } catch (err) {
    container.textContent = NO_WEBGL
    console.error(err)
    return
  }

  map.on('error', (e) => {
    // A tile error carries `tile`/`sourceId` (maplibre-gl tile/tile_manager.ts:197);
    // a style-load failure fires a bare ErrorEvent (maplibre-gl style/style.ts:449).
    // isStyleLoaded() can't tell these apart: it's false during any in-flight tile.
    if (e.tile || e.sourceId) {
      console.error(e.error)
      return
    }
    container.textContent = LOAD_FAILED
    console.error(e.error)
  })

  let timer = 0
  map.on('moveend', () => {
    clearTimeout(timer)
    timer = setTimeout(() => saveView(store, {
      center: map.getCenter().toArray(),
      zoom: map.getZoom(),
      bearing: map.getBearing(),
      pitch: map.getPitch(),
    }), SAVE_DELAY)
  })

  attach(map)
  addStyleControl(map, store, style)
  render(<Places map={map} />, document.getElementById('panel'))

  window.mapper = { map }
}

start()
```

- [ ] **Step 6: Write the failing spec**

Append to `test/map.spec.js`:

```js
const textSize = (page, id) => page.evaluate(
  (layerId) => window.mapper.map.getStyle().layers.find((l) => l.id === layerId).layout['text-size'], id)

const minZoom = (page, id) => page.evaluate(
  (layerId) => window.mapper.map.getStyle().layers.find((l) => l.id === layerId).minzoom, id)

test('stored tweaks are applied to the startup style', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.tweaks', JSON.stringify({ textScale: 1.5, buildingMinZoom: 15 }))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  expect(await textSize(page, 'place-label')).toBe(18)
  expect(await minZoom(page, 'building')).toBe(15)
})
```

- [ ] **Step 7: Run the whole gate**

Run: `cd /home/john/src/wider/mapper && npm test`
Expected: PASS, both suites, 0 failures. The added spec passes, and every
existing spec including `a style load failure shows the failure message` and
`a failed tile leaves a drawn map in place` still passes.

- [ ] **Step 8: Commit**

```bash
cd /home/john/src/wider/mapper
git add src/main.jsx src/styles.jsx src/tweaks.jsx test/harness.js test/map.spec.js
git commit -m "Fetch and transform the startup style instead of loading it by URL"
```

---

### Task 3: The stepper rows

**Files:**
- Modify: `src/tweaks.jsx` (replace the Task 2 stub)
- Modify: `src/styles.jsx` (`addStyleControl`'s render)
- Modify: `src/style.css` (append)
- Test: `test/map.spec.js` (added specs)

**Model:** `sonnet` — component wiring plus four browser specs.

**Interfaces:**
- Consumes: `TEXT_SCALES`, `BUILDING_ZOOMS`, `DEFAULT_TWEAKS`, `saveTweaks`,
  `applyTweaks` from `src/tweaks.js`; the `fetched` holder and `tweaks` signal
  from Task 2.
- Produces:
  - `Steppers({ onChange })` from `src/tweaks.jsx`, where `onChange` receives a
    complete `{ textScale, buildingMinZoom }`.
  - DOM contract the specs pin: each row is `#styles .tweak-row`; its buttons
    are `.tweak-down[data-tweak="text"|"buildings"]` and
    `.tweak-up[data-tweak=...]`; the reading is
    `.tweak-value[data-tweak=...]`.

- [ ] **Step 1: Write the failing specs**

Append to `test/map.spec.js`:

```js
const down = (id) => '#styles .tweak-down[data-tweak="' + id + '"]'
const up = (id) => '#styles .tweak-up[data-tweak="' + id + '"]'
const reading = (id) => '#styles .tweak-value[data-tweak="' + id + '"]'

test('stepping Text up scales the labels and fetches no style', async ({ page }) => {
  await open(page)
  let styleRequests = 0
  page.on('request', (r) => { if (r.url().includes('/styles/')) styleRequests += 1 })
  await page.click(up('text'))
  await expect(page.locator(reading('text'))).toHaveText('110%')
  await expect.poll(() => textSize(page, 'place-label')).toBeCloseTo(13.2, 5)
  // 10 * 1.1 is 11.000000000000002, so compare the stops element by element.
  const interp = await textSize(page, 'poi-label')
  expect(interp.slice(0, 3)).toEqual(['interpolate', ['linear'], ['zoom']])
  expect(interp[3]).toBe(10)
  expect(interp[4]).toBeCloseTo(11, 5)
  expect(interp[5]).toBe(16)
  expect(interp[6]).toBeCloseTo(22, 5)
  expect(styleRequests).toBe(0)
})

test('stepping Buildings up raises the building layer minzoom', async ({ page }) => {
  await open(page)
  await page.click(up('buildings'))
  await expect(page.locator(reading('buildings'))).toHaveText('14')
  await expect.poll(() => minZoom(page, 'building')).toBe(14)
})

test('both steppers survive a reload', async ({ page }) => {
  await open(page)
  await page.click(up('text'))
  await page.click(up('buildings'))
  await expect.poll(() => page.evaluate(() => localStorage.getItem('mapper.tweaks')))
    .toContain('1.1')
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await expect(page.locator(reading('text'))).toHaveText('110%')
  await expect(page.locator(reading('buildings'))).toHaveText('14')
  expect(await minZoom(page, 'building')).toBe(14)
})

test('the steppers disable at the ends of their ranges', async ({ page }) => {
  await open(page)
  await expect(page.locator(down('text'))).toBeDisabled()
  await expect(page.locator(down('buildings'))).toBeDisabled()
  await expect(page.locator(up('text'))).toBeEnabled()
  for (let i = 0; i < 5; i += 1) await page.click(up('text'))
  await expect(page.locator(reading('text'))).toHaveText('150%')
  await expect(page.locator(up('text'))).toBeDisabled()
  await expect(page.locator(down('text'))).toBeEnabled()
  for (let i = 0; i < 3; i += 1) await page.click(up('buildings'))
  await expect(page.locator(reading('buildings'))).toHaveText('16')
  await expect(page.locator(up('buildings'))).toBeDisabled()
})

test('switching style keeps the current tweaks applied', async ({ page }) => {
  await open(page)
  await page.click(up('text'))
  await page.click(up('buildings'))
  await page.click('#styles .style-button[data-style="dark"]')
  await expect.poll(() => styleName(page)).toBe('dark')
  await expect.poll(() => textSize(page, 'place-label')).toBeCloseTo(13.2, 5)
  expect(await minZoom(page, 'building')).toBe(14)
  await expect(page.locator(reading('text'))).toHaveText('110%')
})
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd /home/john/src/wider/mapper && npx playwright test -g "stepper|steppers|Stepping|stepping|Buildings|tweaks applied"`
Expected: FAIL, the click times out because `.tweak-up` does not exist.

- [ ] **Step 3: Write the stepper component**

Replace `src/tweaks.jsx` entirely:

```jsx
import { signal } from '@preact/signals'

import { TEXT_SCALES, BUILDING_ZOOMS, DEFAULT_TWEAKS } from './tweaks.js'

export const tweaks = signal(DEFAULT_TWEAKS)

function Row({ id, label, notches, value, text, less, more, pick }) {
  const i = notches.indexOf(value)
  return (
    <div class="tweak-row">
      <span class="tweak-label">{label}</span>
      <button
        class="tweak-down"
        data-tweak={id}
        title={less}
        disabled={i <= 0}
        onClick={() => pick(notches[i - 1])}
      >
        −
      </button>
      <span class="tweak-value" data-tweak={id}>{text}</span>
      <button
        class="tweak-up"
        data-tweak={id}
        title={more}
        disabled={i >= notches.length - 1}
        onClick={() => pick(notches[i + 1])}
      >
        +
      </button>
    </div>
  )
}

export function Steppers({ onChange }) {
  const t = tweaks.value
  return (
    <div id="tweaks">
      <Row
        id="text"
        label="Text"
        notches={TEXT_SCALES}
        value={t.textScale}
        text={Math.round(t.textScale * 100) + '%'}
        less="Smaller labels"
        more="Larger labels"
        pick={(v) => onChange({ ...t, textScale: v })}
      />
      <Row
        id="buildings"
        label="Buildings"
        notches={BUILDING_ZOOMS}
        value={t.buildingMinZoom}
        text={String(t.buildingMinZoom)}
        less="Buildings from further out"
        more="Buildings only closer in"
        pick={(v) => onChange({ ...t, buildingMinZoom: v })}
      />
    </div>
  )
}
```

- [ ] **Step 4: Render the steppers in the style control**

In `src/styles.jsx`, widen the `tweaks.jsx` import:

```js
import { tweaks, Steppers } from './tweaks.jsx'
```

and add `saveTweaks` to the `tweaks.js` import:

```js
import { loadTweaks, saveTweaks, applyTweaks } from './tweaks.js'
```

Then replace the `onAdd` body in `addStyleControl` so the control renders the
buttons, a divider, and the steppers:

```jsx
  const change = (next) => {
    const clean = saveTweaks(store, next)
    if (!clean) return
    tweaks.value = clean
    if (fetched) map.setStyle(applyTweaks(fetched, clean))
  }

  map.addControl({
    onAdd() {
      const el = document.createElement('div')
      el.id = 'styles'
      el.className = 'maplibregl-ctrl maplibregl-ctrl-group'
      render(
        <>
          <Buttons map={map} store={store} />
          <div class="tweak-divider" />
          <Steppers onChange={change} />
        </>,
        el,
      )
      return el
    },
    onRemove() {},
  }, 'top-right')
```

- [ ] **Step 5: Style the divider and the rows**

Append to `src/style.css`:

```css
#styles .tweak-divider {
  height: 1px;
  margin: 4px 0;
  background: rgba(0, 0, 0, 0.15);
}

#styles .tweak-row {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  color: #111;
}

#styles .tweak-label {
  flex: 1;
}

#styles .tweak-value {
  min-width: 2.6rem;
  text-align: center;
  font-variant-numeric: tabular-nums;
}

#styles .tweak-row button {
  width: 1.4rem;
  height: 1.4rem;
  padding: 0;
  border: 0;
  background: none;
  color: #111;
  font: inherit;
  cursor: pointer;
}

#styles .tweak-row button:hover:not(:disabled) {
  background: rgba(0, 0, 0, 0.07);
}

#styles .tweak-row button:disabled {
  color: #aaa;
  cursor: default;
}
```

- [ ] **Step 6: Run the whole gate**

Run: `cd /home/john/src/wider/mapper && npm test`
Expected: PASS, both suites, 0 failures.

- [ ] **Step 7: Commit**

```bash
cd /home/john/src/wider/mapper
git add src/tweaks.jsx src/styles.jsx src/style.css test/map.spec.js
git commit -m "Add the Text and Buildings steppers to the style control"
```

---

### Task 4: Documentation

**Files:**
- Modify: `docs/user-manual.md` (the "Map style" section)
- Modify: `docs/architecture.md` (the "UI" section)
- Modify: `docs/backlog.md:6-13`

**Model:** `haiku` — the replacement text is given verbatim below.

**Interfaces:**
- Consumes: the behavior landed in Tasks 1-3. Nothing produces anything.

- [ ] **Step 1: Document the steppers in the user manual**

In `docs/user-manual.md`, append to the "Map style" section, after the
paragraph ending "…all survive a switch.":

```markdown
Below the style buttons, two steppers adjust how the chosen style draws:

- **Text** scales every label in the style, from 100% to 150% in ten-point
  steps.
- **Buildings** sets the zoom below which buildings are not drawn: 13, 14, 15,
  or 16. Buildings only exist in the tiles from zoom 13, so 13 is the default
  and draws them as early as the data allows.

Both settings apply to whichever style is showing and are saved to
`localStorage` under `mapper.tweaks`. A missing or unrecognised value falls
back to 100% text and buildings from zoom 13.
```

- [ ] **Step 2: Record the startup change in architecture.md**

In `docs/architecture.md`, in the "UI" section, replace the final sentence of
the paragraph about switching (line 62-63, "Startup still passes MapLibre a
style URL, which keeps a launch-time failure on the existing
`map.on('error')` path.") with:

```markdown
Startup no longer passes MapLibre a style URL. `main.jsx` fetches the style
JSON itself, runs it through `applyTweaks`, and constructs the map from the
resulting object, because MapLibre's `transformStyle` hook exists only on
`setStyle` and not on the map constructor. A failed startup fetch shows the
style-load message directly; a body MapLibre rejects still reaches
`map.on('error')`, because the map is constructed through the validating path.

`styles.jsx` holds the style as fetched, untransformed, so moving a stepper
re-transforms that held object rather than refetching. `applyTweaks` returns a
new style for the same reason: the held object is transformed repeatedly, and a
mutating transform would compound scale on scale. The transform reads the tweak
values at the moment it applies rather than when the click happened, so a
stepper moved during an in-flight switch is carried by that switch when it
lands.
```

Also add `src/tweaks.js` to the list of store-argument-taking pure modules by
replacing line 37's "`src/view.js` and `src/places.js` take" with
"`src/view.js`, `src/places.js` and `src/tweaks.js` take".

- [ ] **Step 3: Rewrite the backlog entry**

In `docs/backlog.md`, replace the entry at lines 6-13 (from "A control for how
much the map draws when zoomed out" through "rather than more detail.") with:

```markdown
- Per-style memory of the Text and Buildings settings. One setting shared by
  all five styles is a statement about the screen, not about Liberty. What a
  style shows at a given zoom is mostly its own zoom-interpolated opacity and
  label collision, which the Buildings floor cannot reach, and beneath that the
  tiles have hard floors: buildings only exist from zoom 13, POIs from 11, road
  labels from 6.
- The vector source ends at zoom 14, so a close-up past that is magnified z14
  data rather than more detail.
```

- [ ] **Step 4: Verify nothing else names the old startup path**

Run: `cd /home/john/src/wider/mapper && grep -rn "style URL\|styleUrl\|by URL" docs README.md`
Expected: no hit claiming startup loads a style by URL.

- [ ] **Step 5: Run the whole gate one last time**

Run: `cd /home/john/src/wider/mapper && npm test`
Expected: PASS, both suites, 0 failures.

- [ ] **Step 6: Commit**

```bash
cd /home/john/src/wider/mapper
git add docs/user-manual.md docs/architecture.md docs/backlog.md
git commit -m "Document the Text and Buildings steppers and the fetched startup style"
```

---

## Left out, deliberately

Per-style memory of these settings, and `icon-size` scaling. Both are named in
the spec's "Left out" section. The per-style half stays in the backlog.
