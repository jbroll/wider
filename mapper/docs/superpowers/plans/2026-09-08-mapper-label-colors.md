# mapper label colors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four label-color pickers (Places, Streets, POIs, Water) to mapper's style control, applied as a pure transform over the fetched style and remembered in `localStorage`.

**Architecture:** A new pure module `src/colors.js` holds the group table, per-group validation, the `mapper.colors` store round trip, and `applyColors(style, colors)`, which returns a new style with recolored `text-color`, a contrast-chosen `text-halo-color`, and a `text-halo-width` of 1 only where none exists. `src/colors.jsx` holds the signal, the DOM-dependent seeding of an unset swatch from the current style, and the four picker rows. `styles.jsx` composes `applyColors` over `applyTweaks` on the style it already holds as fetched, so a picker move refetches nothing.

**Tech Stack:** Preact + `@preact/signals`, MapLibre GL JS 5, esbuild, `node --test` for pure modules, Playwright for the browser.

## Global Constraints

- Both transforms must not mutate their input. `styles.jsx` re-transforms the same fetched object on every change.
- Store key is `mapper.colors`, beside `mapper.view`, `mapper.places`, `mapper.style` and `mapper.tweaks`.
- Accepted colors are `#rgb` and `#rrggbb`, case-insensitive. A `null`, missing, or malformed group falls back on its own without disturbing the other three. This differs deliberately from `mapper.tweaks`, which is all-or-nothing.
- `colors.js` stays pure and browser-free: it never converts a color, it only ever writes the `#rgb` or `#rrggbb` the user picked. Anything needing a DOM lives in `colors.jsx`.
- `icon-color` is never touched.
- Existing `text-halo-width` values are preserved. Only an absent one becomes `1`.
- Halo color is `#ffffff` below WCAG relative luminance 0.5 and `#000000` at or above it.
- A symbol layer with no `text-color` is left alone. No special case for route shields.
- No picker is greyed out or hidden by what the current style contains.
- Docs change in the same commit as the code.

## File Structure

- `src/colors.js` — group table, validation, load/save, `applyColors`. Pure, no DOM.
- `src/colors.jsx` — `colors` and `styleColors` signals, `toHex`, `seedColors`, `Pickers`. Needs a DOM.
- `src/styles.jsx` — composes the two transforms, re-applies on a picker move, renders the rows below a second divider.
- `src/main.jsx` — composes `applyColors` over `applyTweaks` at startup.
- `src/style.css` — picker row styling. The divider reuses `.tweak-divider`.
- `test/colors.test.js` — `node --test` cover of the pure module.
- `test/harness.js` — stub style gains one labelled layer per group plus a shield.
- `test/map.spec.js` — added Playwright specs.

`src/tweaks.js` and `src/map.js` are unchanged.

---

### Task 1: The pure colors module

**Files:**
- Create: `mapper/src/colors.js`
- Test: `mapper/test/colors.test.js`

**Model:** `sonnet` — the transform and the luminance rule are implemented from prose, and the group/paint interactions need judgment.

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `COLORS_KEY: string` — `'mapper.colors'`
  - `GROUPS: Array<{ id: string, label: string, sourceLayers: string[] }>` — in order: `places`/`Places`/`['place']`, `streets`/`Streets`/`['transportation_name']`, `pois`/`POIs`/`['poi', 'aerodrome_label']`, `water`/`Water`/`['water_name', 'waterway']`
  - `DEFAULT_COLORS: { places: null, streets: null, pois: null, water: null }`
  - `validateColor(value: unknown): string | null`
  - `validateColors(value: unknown): { places, streets, pois, water }` — always all four keys, `null` where unset
  - `parseColors(raw: unknown)` / `loadColors(store)` / `saveColors(store, colors)` — same shape as `tweaks.js`
  - `luminance(hex: string): number`
  - `haloFor(hex: string): '#ffffff' | '#000000'`
  - `applyColors(style, colors): style` — new object, input untouched

- [ ] **Step 1: Write the failing test**

Create `mapper/test/colors.test.js`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  COLORS_KEY, GROUPS, DEFAULT_COLORS,
  validateColor, validateColors, parseColors, loadColors, saveColors,
  luminance, haloFor, applyColors,
} from '../src/colors.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    raw: map,
  }
}

function stub() {
  return {
    version: 8,
    name: 'stub',
    sources: {},
    layers: [
      { id: 'bg', type: 'background', paint: { 'background-color': '#fff' } },
      {
        id: 'place-label',
        type: 'symbol',
        'source-layer': 'place',
        paint: { 'text-color': '#333', 'text-halo-color': '#fff', 'text-halo-width': 1.4 },
      },
      {
        id: 'street-label',
        type: 'symbol',
        'source-layer': 'transportation_name',
        paint: { 'text-color': '#666' },
      },
      {
        id: 'street-shield',
        type: 'symbol',
        'source-layer': 'transportation_name',
        paint: { 'icon-opacity': 1 },
      },
      {
        id: 'poi-label',
        type: 'symbol',
        'source-layer': 'poi',
        paint: { 'text-color': '#666', 'text-halo-width': 1, 'icon-color': '#900' },
      },
      {
        id: 'airport-label',
        type: 'symbol',
        'source-layer': 'aerodrome_label',
        paint: { 'text-color': '#666', 'text-halo-width': 1 },
      },
      {
        id: 'water-label',
        type: 'symbol',
        'source-layer': 'water_name',
        paint: { 'text-color': '#495e91', 'text-halo-width': 1 },
      },
      {
        id: 'river-label',
        type: 'symbol',
        'source-layer': 'waterway',
        paint: { 'text-color': '#74aee9', 'text-halo-width': 1 },
      },
      { id: 'building', type: 'fill', 'source-layer': 'building', paint: { 'fill-color': '#ddd' } },
      { id: 'road', type: 'line', 'source-layer': 'transportation', paint: { 'line-color': '#eee' } },
    ],
  }
}

const layer = (style, id) => style.layers.find((l) => l.id === id)

const SET = { places: '#1a1a1a', streets: null, pois: '#7a4f00', water: null }

test('the groups are the four listed ones', () => {
  assert.deepEqual(GROUPS.map((g) => g.id), ['places', 'streets', 'pois', 'water'])
  assert.deepEqual(GROUPS.map((g) => g.label), ['Places', 'Streets', 'POIs', 'Water'])
  assert.deepEqual(GROUPS.map((g) => g.sourceLayers), [
    ['place'], ['transportation_name'], ['poi', 'aerodrome_label'], ['water_name', 'waterway'],
  ])
  assert.deepEqual(DEFAULT_COLORS, { places: null, streets: null, pois: null, water: null })
})

test('a color is #rgb or #rrggbb, case-insensitive', () => {
  assert.equal(validateColor('#abc'), '#abc')
  assert.equal(validateColor('#A1B2C3'), '#A1B2C3')
  assert.equal(validateColor('#1a1a1a'), '#1a1a1a')
  assert.equal(validateColor('red'), null)
  assert.equal(validateColor('#12345'), null)
  assert.equal(validateColor('rgb(1,2,3)'), null)
  assert.equal(validateColor(7), null)
  assert.equal(validateColor(null), null)
})

test('a saved colors value round-trips', () => {
  const store = fakeStore()
  assert.deepEqual(saveColors(store, SET), SET)
  assert.deepEqual(loadColors(store), SET)
  assert.equal(store.raw.size, 1)
  assert.ok(store.raw.has(COLORS_KEY))
})

test('a missing key gives all four groups unset', () => {
  assert.deepEqual(loadColors(fakeStore()), DEFAULT_COLORS)
})

test('a malformed document gives all four groups unset', () => {
  assert.deepEqual(loadColors(fakeStore({ [COLORS_KEY]: '{not json' })), DEFAULT_COLORS)
  assert.deepEqual(parseColors('[]'), DEFAULT_COLORS)
  assert.deepEqual(parseColors('null'), DEFAULT_COLORS)
  assert.deepEqual(parseColors(null), DEFAULT_COLORS)
})

test('a bad value in one group leaves the other three standing', () => {
  const raw = JSON.stringify({ places: '#1a1a1a', streets: 'blue', pois: 12, water: '#0f0' })
  assert.deepEqual(parseColors(raw), {
    places: '#1a1a1a', streets: null, pois: null, water: '#0f0',
  })
})

test('an unknown key is dropped and a missing one is null', () => {
  assert.deepEqual(validateColors({ places: '#000', bogus: '#fff' }), {
    places: '#000', streets: null, pois: null, water: null,
  })
})

test('the halo flips at the luminance threshold', () => {
  assert.equal(haloFor('#000000'), '#ffffff')
  assert.equal(haloFor('#ffffff'), '#000000')
  assert.ok(luminance('#bababa') < 0.5)
  assert.ok(luminance('#bcbcbc') >= 0.5)
  assert.equal(haloFor('#bababa'), '#ffffff')
  assert.equal(haloFor('#bcbcbc'), '#000000')
  assert.equal(haloFor('#fff'), '#000000')
})

test('a group recolors its own source-layers and no others', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, pois: '#7a4f00' })
  assert.equal(layer(out, 'poi-label').paint['text-color'], '#7a4f00')
  assert.equal(layer(out, 'airport-label').paint['text-color'], '#7a4f00')
  assert.equal(layer(out, 'place-label').paint['text-color'], '#333')
  assert.equal(layer(out, 'street-label').paint['text-color'], '#666')
  assert.equal(layer(out, 'water-label').paint['text-color'], '#495e91')
  assert.equal(layer(out, 'river-label').paint['text-color'], '#74aee9')
})

test('Water covers both water_name and waterway', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, water: '#0088ff' })
  assert.equal(layer(out, 'water-label').paint['text-color'], '#0088ff')
  assert.equal(layer(out, 'river-label').paint['text-color'], '#0088ff')
})

test('a layer with no text-color is left alone', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, streets: '#1a1a1a' })
  assert.deepEqual(layer(out, 'street-shield'), layer(stub(), 'street-shield'))
  assert.deepEqual(layer(out, 'road'), layer(stub(), 'road'))
  assert.deepEqual(layer(out, 'building'), layer(stub(), 'building'))
  assert.deepEqual(layer(out, 'bg'), layer(stub(), 'bg'))
})

test('the halo color follows the chosen color', () => {
  const dark = applyColors(stub(), { ...DEFAULT_COLORS, places: '#1a1a1a' })
  assert.equal(layer(dark, 'place-label').paint['text-halo-color'], '#ffffff')
  const light = applyColors(stub(), { ...DEFAULT_COLORS, places: '#eeeeee' })
  assert.equal(layer(light, 'place-label').paint['text-halo-color'], '#000000')
})

test('an absent halo width becomes 1 and an existing one survives', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, places: '#1a1a1a', streets: '#1a1a1a' })
  assert.equal(layer(out, 'street-label').paint['text-halo-width'], 1)
  assert.equal(layer(out, 'place-label').paint['text-halo-width'], 1.4)
})

test('icon-color is not touched', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, pois: '#7a4f00' })
  assert.equal(layer(out, 'poi-label').paint['icon-color'], '#900')
})

test('a null or malformed group leaves that group alone', () => {
  const out = applyColors(stub(), { places: '#1a1a1a', streets: 'blue', pois: null, water: undefined })
  assert.equal(layer(out, 'place-label').paint['text-color'], '#1a1a1a')
  assert.deepEqual(layer(out, 'street-label'), layer(stub(), 'street-label'))
  assert.deepEqual(layer(out, 'poi-label'), layer(stub(), 'poi-label'))
  assert.deepEqual(layer(out, 'water-label'), layer(stub(), 'water-label'))
})

test('the default colors leave a style alone', () => {
  assert.deepEqual(applyColors(stub(), DEFAULT_COLORS), stub())
  assert.deepEqual(applyColors(stub(), null), stub())
  assert.deepEqual(applyColors(stub(), 'nonsense'), stub())
})

test('the input style is not mutated', () => {
  const input = stub()
  const before = JSON.stringify(input)
  const out = applyColors(input, SET)
  assert.equal(JSON.stringify(input), before)
  assert.notEqual(out, input)
  assert.notEqual(out.layers, input.layers)
})

test('applying twice to the same input does not compound', () => {
  const input = stub()
  assert.deepEqual(applyColors(input, SET), applyColors(input, SET))
})

test('a style with no layers is returned as it is', () => {
  assert.equal(applyColors(null, SET), null)
  assert.deepEqual(applyColors({ version: 8 }, SET), { version: 8 })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd mapper && node --test test/colors.test.js`
Expected: FAIL — `Cannot find module '.../src/colors.js'`

- [ ] **Step 3: Write the implementation**

Create `mapper/src/colors.js`:

```js
export const COLORS_KEY = 'mapper.colors'

// Airport names sit with the POIs and river names with the water because that
// is how the styles color them: Liberty gives aerodrome_label the same #666 as
// its poi layers, and waterway the #74aee9 beside water_name's #495e91.
export const GROUPS = [
  { id: 'places', label: 'Places', sourceLayers: ['place'] },
  { id: 'streets', label: 'Streets', sourceLayers: ['transportation_name'] },
  { id: 'pois', label: 'POIs', sourceLayers: ['poi', 'aerodrome_label'] },
  { id: 'water', label: 'Water', sourceLayers: ['water_name', 'waterway'] },
]

export const DEFAULT_COLORS = { places: null, streets: null, pois: null, water: null }

const GROUP_OF = new Map()
for (const g of GROUPS) for (const name of g.sourceLayers) GROUP_OF.set(name, g.id)

const HEX = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i

export function validateColor(value) {
  return typeof value === 'string' && HEX.test(value) ? value : null
}

// Per group rather than all-or-nothing like validateTweaks: four independent
// colors, so a malformed one must not clear the other three.
export function validateColors(value) {
  const ok = value && typeof value === 'object' && !Array.isArray(value)
  const out = {}
  for (const g of GROUPS) out[g.id] = ok ? validateColor(value[g.id]) : null
  return out
}

export function parseColors(raw) {
  if (typeof raw !== 'string') return { ...DEFAULT_COLORS }
  try {
    return validateColors(JSON.parse(raw))
  } catch {
    return { ...DEFAULT_COLORS }
  }
}

export function loadColors(store) {
  return parseColors(store.getItem(COLORS_KEY))
}

export function saveColors(store, colors) {
  const clean = validateColors(colors)
  store.setItem(COLORS_KEY, JSON.stringify(clean))
  return clean
}

// WCAG relative luminance.
export function luminance(hex) {
  const h = hex.slice(1)
  const full = h.length === 3 ? h[0] + h[0] + h[1] + h[1] + h[2] + h[2] : h
  const chan = (i) => {
    const c = parseInt(full.slice(i * 2, i * 2 + 2), 16) / 255
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * chan(0) + 0.7152 * chan(1) + 0.0722 * chan(2)
}

export function haloFor(hex) {
  return luminance(hex) < 0.5 ? '#ffffff' : '#000000'
}

// MapLibre's default halo width is 0, so a halo color set on a layer that
// declares no width would be invisible. An existing width is left alone: the
// styles' 0.5 to 2 is what separates a country name from a town name.
function recolor(layer, color) {
  const paint = { ...layer.paint, 'text-color': color, 'text-halo-color': haloFor(color) }
  if (paint['text-halo-width'] === undefined) paint['text-halo-width'] = 1
  return { ...layer, paint }
}

// Returns a new style, like applyTweaks: mapper re-transforms the style it
// holds as fetched on every change.
//
// A symbol layer with no text-color draws no text of its own, which is what
// excludes the route shields - their number is on a sprite badge - with no
// special case for them.
export function applyColors(style, colors) {
  const clean = validateColors(colors)
  if (!style || !Array.isArray(style.layers)) return style
  const layers = style.layers.map((layer) => {
    if (layer.type !== 'symbol' || !layer.paint) return layer
    if (layer.paint['text-color'] === undefined) return layer
    const group = GROUP_OF.get(layer['source-layer'])
    const color = group ? clean[group] : null
    return color ? recolor(layer, color) : layer
  })
  return { ...style, layers }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd mapper && node --test test/colors.test.js`
Expected: PASS, 18 tests, 0 failures.

- [ ] **Step 5: Run the whole node suite to check nothing regressed**

Run: `cd mapper && node --test test/*.test.js`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add mapper/src/colors.js mapper/test/colors.test.js
git commit -m "Add the pure label-colors module"
```

---

### Task 2: Stub layers per group in the Playwright harness

**Files:**
- Modify: `mapper/test/harness.js:24-64`

**Model:** `haiku` — the complete replacement text is given below.

**Interfaces:**
- Consumes: nothing.
- Produces: `LABEL_COLORS: Record<styleId, string>` exported from `test/harness.js`, and a `styleFor(id)` whose layers are `bg`, `place-label` (`source-layer: place`, `text-color: '#334455'`, `text-halo-width: 1.4`), `poi-label` (`source-layer: poi`, `text-color: '#666666'`, `text-halo-width: 1`), `street-label` (`source-layer: transportation_name`, `text-color: LABEL_COLORS[id]`, no `text-halo-width`), `street-shield` (`source-layer: transportation_name`, no `text-color`), `water-label` (`source-layer: water_name`, `text-color: 'hsl(210, 50%, 40%)'` which normalizes to `#336699`, `text-halo-width: 1`), and `building`.

- [ ] **Step 1: Replace the stub style block**

In `mapper/test/harness.js`, replace everything from the `// The background layer needs no source.` comment through the closing brace of `styleFor` (lines 22-64) with:

```js
// The background layer needs no source. The symbol layers sit on an empty
// inline GeoJSON source and carry no text-field, so neither tiles nor glyphs
// are ever fetched for them. The building layer needs a vector source to carry
// a source-layer; its tiles are declared inline so no TileJSON is fetched, and
// routeStyle aborts any request that does reach them. The colour and name
// differ per style so a test can tell which one is drawn.
export const STYLE_COLORS = {
  liberty: '#cfe8cf',
  bright: '#f6f0d8',
  positron: '#f4f4f4',
  dark: '#222222',
  fiord: '#4a5568',
}

// The Streets label color differs per style so a test can watch an unset
// swatch re-seed on a switch.
export const LABEL_COLORS = {
  liberty: '#666666',
  bright: '#886644',
  positron: '#444444',
  dark: '#504e4e',
  fiord: '#333333',
}

// One labelled layer per color group, plus a shield with no text-color and a
// water label whose color is an hsl() the seeding code has to normalise.
// street-label declares no text-halo-width, so the transform's absent-width
// clause is exercised too.
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
      {
        id: 'place-label',
        type: 'symbol',
        source: 'empty',
        'source-layer': 'place',
        layout: { 'text-size': 12 },
        paint: { 'text-color': '#334455', 'text-halo-color': '#ffffff', 'text-halo-width': 1.4 },
      },
      {
        id: 'poi-label',
        type: 'symbol',
        source: 'empty',
        'source-layer': 'poi',
        layout: { 'text-size': ['interpolate', ['linear'], ['zoom'], 10, 10, 16, 20] },
        paint: { 'text-color': '#666666', 'text-halo-width': 1 },
      },
      {
        id: 'street-label',
        type: 'symbol',
        source: 'empty',
        'source-layer': 'transportation_name',
        layout: { 'text-size': 12 },
        paint: { 'text-color': LABEL_COLORS[id] || '#666666' },
      },
      {
        id: 'street-shield',
        type: 'symbol',
        source: 'empty',
        'source-layer': 'transportation_name',
        layout: { 'text-size': 12 },
        paint: { 'icon-opacity': 1 },
      },
      {
        id: 'water-label',
        type: 'symbol',
        source: 'empty',
        'source-layer': 'water_name',
        layout: { 'text-size': 12 },
        paint: { 'text-color': 'hsl(210, 50%, 40%)', 'text-halo-width': 1 },
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

- [ ] **Step 2: Run the existing Playwright suite to verify the stub is still valid**

Run: `cd mapper && npx playwright test`
Expected: PASS. Every existing spec still passes — the added `source-layer` and `paint` keys do not change any text size or minzoom the existing specs assert on. If a spec fails with a style validation error, the new layers are malformed; fix them before moving on.

- [ ] **Step 3: Commit**

```bash
git add mapper/test/harness.js
git commit -m "Give the Playwright stub style one labelled layer per color group"
```

---

### Task 3: The pickers, the wiring, and the browser specs

**Files:**
- Create: `mapper/src/colors.jsx`
- Modify: `mapper/src/styles.jsx`
- Modify: `mapper/src/main.jsx:40`
- Modify: `mapper/src/style.css` (append after the `#styles .tweak-row button:disabled` rule)
- Test: `mapper/test/map.spec.js` (append)

**Model:** `sonnet` — four files coordinated, plus signal and MapLibre-control wiring.

**Interfaces:**
- Consumes: `GROUPS`, `DEFAULT_COLORS`, `loadColors`, `saveColors`, `applyColors` from `src/colors.js` (Task 1); `LABEL_COLORS`, `styleFor` from `test/harness.js` (Task 2).
- Produces from `src/colors.jsx`:
  - `colors: Signal<{ places, streets, pois, water }>` — the chosen colors, `null` where unset
  - `styleColors: Signal<{ places, streets, pois, water }>` — the current style's own color per group, always `#rrggbb`
  - `toHex(css: string): string | null`
  - `seedColors(style): { places, streets, pois, water }`
  - `Pickers({ onChange })` — four rows; `onChange` receives the full next colors object
- DOM contract for the specs: `input.color-swatch[data-color="<group>"]` and `button.color-clear[data-color="<group>"]`, both inside `#styles`.

- [ ] **Step 1: Write the failing specs**

Append to `mapper/test/map.spec.js`:

```js
const paintOf = (page, id, prop) => page.evaluate(
  ([layerId, name]) => window.mapper.map.getStyle().layers.find((l) => l.id === layerId).paint[name],
  [id, prop])

const swatch = (id) => '#styles .color-swatch[data-color="' + id + '"]'
const clearer = (id) => '#styles .color-clear[data-color="' + id + '"]'

test('setting the Streets color recolors that layer and fetches no style', async ({ page }) => {
  await open(page)
  let styleRequests = 0
  page.on('request', (r) => { if (r.url().includes('/styles/')) styleRequests += 1 })
  await page.locator(swatch('streets')).fill('#1a1a1a')
  await expect.poll(() => paintOf(page, 'street-label', 'text-color')).toBe('#1a1a1a')
  expect(await paintOf(page, 'street-label', 'text-halo-color')).toBe('#ffffff')
  expect(await paintOf(page, 'street-label', 'text-halo-width')).toBe(1)
  expect(styleRequests).toBe(0)
})

test('a light color gets a black halo', async ({ page }) => {
  await open(page)
  await page.locator(swatch('places')).fill('#eeeeee')
  await expect.poll(() => paintOf(page, 'place-label', 'text-halo-color')).toBe('#000000')
  expect(await paintOf(page, 'place-label', 'text-halo-width')).toBe(1.4)
})

test('setting a color leaves the other three groups alone', async ({ page }) => {
  await open(page)
  await page.locator(swatch('streets')).fill('#1a1a1a')
  await expect.poll(() => paintOf(page, 'street-label', 'text-color')).toBe('#1a1a1a')
  expect(await paintOf(page, 'place-label', 'text-color')).toBe('#334455')
  expect(await paintOf(page, 'poi-label', 'text-color')).toBe('#666666')
  expect(await paintOf(page, 'water-label', 'text-color')).toBe('hsl(210, 50%, 40%)')
})

test('the shield layer is untouched by a Streets color', async ({ page }) => {
  await open(page)
  await page.locator(swatch('streets')).fill('#1a1a1a')
  await expect.poll(() => paintOf(page, 'street-label', 'text-color')).toBe('#1a1a1a')
  expect(await paintOf(page, 'street-shield', 'text-color')).toBe(undefined)
  expect(await paintOf(page, 'street-shield', 'text-halo-color')).toBe(undefined)
})

test("an unset swatch shows the style's own color", async ({ page }) => {
  await open(page)
  await expect(page.locator(swatch('places'))).toHaveValue('#334455')
  await expect(page.locator(swatch('streets'))).toHaveValue('#666666')
  await expect(page.locator(swatch('pois'))).toHaveValue('#666666')
  await expect(page.locator(swatch('water'))).toHaveValue('#336699')
})

test('an unset swatch re-seeds when the style is switched', async ({ page }) => {
  await open(page)
  await expect(page.locator(swatch('streets'))).toHaveValue('#666666')
  await page.click('#styles .style-button[data-style="dark"]')
  await expect.poll(() => styleName(page)).toBe('dark')
  await expect(page.locator(swatch('streets'))).toHaveValue('#504e4e')
})

test("clearing a group restores the style's own color", async ({ page }) => {
  await open(page)
  await page.locator(swatch('streets')).fill('#1a1a1a')
  await expect.poll(() => paintOf(page, 'street-label', 'text-color')).toBe('#1a1a1a')
  await page.click(clearer('streets'))
  await expect.poll(() => paintOf(page, 'street-label', 'text-color')).toBe('#666666')
  expect(await paintOf(page, 'street-label', 'text-halo-color')).toBe(undefined)
  await expect(page.locator(swatch('streets'))).toHaveValue('#666666')
})

test('the clear button is disabled while its group is unset', async ({ page }) => {
  await open(page)
  await expect(page.locator(clearer('streets'))).toBeDisabled()
  await page.locator(swatch('streets')).fill('#1a1a1a')
  await expect(page.locator(clearer('streets'))).toBeEnabled()
  await expect(page.locator(clearer('places'))).toBeDisabled()
  await page.click(clearer('streets'))
  await expect(page.locator(clearer('streets'))).toBeDisabled()
})

test('colors survive a reload', async ({ page }) => {
  await open(page)
  await page.locator(swatch('pois')).fill('#7a4f00')
  await expect.poll(() => page.evaluate(() => localStorage.getItem('mapper.colors')))
    .toContain('7a4f00')
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  expect(await paintOf(page, 'poi-label', 'text-color')).toBe('#7a4f00')
  await expect(page.locator(swatch('pois'))).toHaveValue('#7a4f00')
  await expect(page.locator(swatch('places'))).toHaveValue('#334455')
})

test('switching style keeps the current colors applied', async ({ page }) => {
  await open(page)
  await page.locator(swatch('streets')).fill('#1a1a1a')
  await expect.poll(() => paintOf(page, 'street-label', 'text-color')).toBe('#1a1a1a')
  await page.click('#styles .style-button[data-style="dark"]')
  await expect.poll(() => styleName(page)).toBe('dark')
  expect(await paintOf(page, 'street-label', 'text-color')).toBe('#1a1a1a')
  await expect(page.locator(swatch('streets'))).toHaveValue('#1a1a1a')
})

test('a color set during an in-flight switch is carried by that switch', async ({ page }) => {
  await open(page)
  let releaseDark
  const held = new Promise((resolve) => { releaseDark = resolve })
  await page.route('**/tiles.openfreemap.org/styles/dark', async (r) => {
    await held
    return r.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(styleFor('dark')),
    })
  })
  await page.click('#styles .style-button[data-style="dark"]')
  await page.locator(swatch('places')).fill('#1a1a1a')
  releaseDark()
  await expect.poll(() => styleName(page)).toBe('dark')
  await expect.poll(() => paintOf(page, 'place-label', 'text-color')).toBe('#1a1a1a')
})
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `cd mapper && npx playwright test test/map.spec.js -g "color|swatch|halo|shield"`
Expected: FAIL — the `.color-swatch` locators time out because no picker rows exist yet.

- [ ] **Step 3: Write the picker component**

Create `mapper/src/colors.jsx`:

```jsx
import { signal } from '@preact/signals'

import { GROUPS, DEFAULT_COLORS } from './colors.js'

export const colors = signal(DEFAULT_COLORS)

function black() {
  const out = {}
  for (const g of GROUPS) out[g.id] = '#000000'
  return out
}

// What the current style paints each group, so an unset swatch opens on what
// is actually drawn rather than on black.
export const styleColors = signal(black())

// The styles give their colors as #666, #495e91, hsl(30,23%,62%),
// rgba(80, 78, 78, 1) and hsla(228,60%,21%,0.7). <input type="color"> takes
// only #rrggbb, so let the browser do the parsing: it normalises a computed
// color to rgb(r, g, b) whatever form it was written in. An unparseable string
// leaves style.color unset.
export function toHex(css) {
  const el = document.createElement('span')
  el.style.color = css
  if (!el.style.color) return null
  el.style.display = 'none'
  document.body.appendChild(el)
  const computed = getComputedStyle(el).color
  el.remove()
  const m = /^rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(computed)
  if (!m) return null
  return '#' + [1, 2, 3].map((i) => Number(m[i]).toString(16).padStart(2, '0')).join('')
}

export function seedColors(style) {
  const layers = style && Array.isArray(style.layers) ? style.layers : []
  const out = {}
  for (const g of GROUPS) {
    let hex = null
    for (const layer of layers) {
      if (layer.type !== 'symbol' || !layer.paint) continue
      if (!g.sourceLayers.includes(layer['source-layer'])) continue
      if (typeof layer.paint['text-color'] !== 'string') continue
      hex = toHex(layer.paint['text-color'])
      if (hex) break
    }
    out[g.id] = hex || '#000000'
  }
  return out
}

export function Pickers({ onChange }) {
  const chosen = colors.value
  const seeded = styleColors.value
  return (
    <div id="colors">
      {GROUPS.map((g) => (
        <div class="color-row" key={g.id}>
          <span class="color-label">{g.label}</span>
          <input
            type="color"
            class="color-swatch"
            data-color={g.id}
            title={g.label + ' label color'}
            value={chosen[g.id] || seeded[g.id]}
            onInput={(e) => onChange({ ...colors.value, [g.id]: e.currentTarget.value })}
          />
          <button
            class="color-clear"
            data-color={g.id}
            title={'Back to the style’s ' + g.label + ' color'}
            disabled={!chosen[g.id]}
            onClick={() => onChange({ ...colors.value, [g.id]: null })}
          >
            ×
          </button>
        </div>
      ))}
    </div>
  )
}
```

- [ ] **Step 4: Wire the transform into the style control**

In `mapper/src/styles.jsx`, add to the imports after the `tweaks.jsx` line:

```jsx
import { loadColors, saveColors, applyColors } from './colors.js'
import { colors, styleColors, seedColors, Pickers } from './colors.jsx'
```

Add below the `fetched` declaration:

```jsx
// Both transforms read their values at the moment they apply, so a picker
// moved while a switch is in flight is carried by that switch when it lands.
const transform = (style) => applyColors(applyTweaks(style, tweaks.value), colors.value)
```

In `switchStyle`, replace:

```jsx
  fetched = style
  // Read at apply time, not at click time, so a stepper moved while this
  // switch is in flight is carried by the switch when it lands.
  map.setStyle(applyTweaks(style, tweaks.value))
```

with:

```jsx
  fetched = style
  styleColors.value = seedColors(style)
  map.setStyle(transform(style))
```

In `addStyleControl`, replace the opening three lines:

```jsx
  current.value = loadStyle(store)
  tweaks.value = loadTweaks(store)
  fetched = style
```

with:

```jsx
  current.value = loadStyle(store)
  tweaks.value = loadTweaks(store)
  colors.value = loadColors(store)
  fetched = style
  styleColors.value = seedColors(style)
```

Replace the `change` closure:

```jsx
  const change = (next) => {
    const clean = saveTweaks(store, next)
    if (!clean) return
    tweaks.value = clean
    if (fetched) map.setStyle(applyTweaks(fetched, clean))
  }
```

with:

```jsx
  const change = (next) => {
    const clean = saveTweaks(store, next)
    if (!clean) return
    tweaks.value = clean
    if (fetched) map.setStyle(transform(fetched))
  }

  const changeColors = (next) => {
    colors.value = saveColors(store, next)
    if (fetched) map.setStyle(transform(fetched))
  }
```

Replace the rendered fragment:

```jsx
        <>
          <Buttons map={map} store={store} />
          <div class="tweak-divider" />
          <Steppers onChange={change} />
        </>
```

with:

```jsx
        <>
          <Buttons map={map} store={store} />
          <div class="tweak-divider" />
          <Steppers onChange={change} />
          <div class="tweak-divider" />
          <Pickers onChange={changeColors} />
        </>
```

- [ ] **Step 5: Compose the transform at startup**

In `mapper/src/main.jsx`, add to the imports after the `tweaks.js` line:

```jsx
import { loadColors, applyColors } from './colors.js'
```

Replace line 40:

```jsx
    map = createMap(container, loadView(store), applyTweaks(style, loadTweaks(store)))
```

with:

```jsx
    map = createMap(container, loadView(store),
      applyColors(applyTweaks(style, loadTweaks(store)), loadColors(store)))
```

- [ ] **Step 6: Style the picker rows**

Append to `mapper/src/style.css`, after the `#styles .tweak-row button:disabled` rule:

```css
#styles .color-row {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  color: #111;
}

#styles .color-label {
  flex: 1;
}

#styles .color-swatch {
  width: 2.6rem;
  height: 1.4rem;
  padding: 0;
  border: 1px solid rgba(0, 0, 0, 0.25);
  background: none;
  cursor: pointer;
}

#styles .color-clear {
  width: 1.4rem;
  height: 1.4rem;
  padding: 0;
  border: 0;
  background: none;
  color: #111;
  font: inherit;
  cursor: pointer;
}

#styles .color-clear:hover:not(:disabled) {
  background: rgba(0, 0, 0, 0.07);
}

#styles .color-clear:disabled {
  color: #aaa;
  cursor: default;
}
```

- [ ] **Step 7: Run the new specs to verify they pass**

Run: `cd mapper && npx playwright test test/map.spec.js -g "color|swatch|halo|shield"`
Expected: PASS, 11 specs.

If `an unset swatch shows the style's own color` reports `#336699` as something else, the browser rounded the `hsl(210, 50%, 40%)` differently than expected; read the actual value out of the failure and reconcile it against the arithmetic (0.2, 0.4, 0.6 → 51, 102, 153) before changing the assertion.

- [ ] **Step 8: Run the whole suite**

Run: `cd mapper && npm test`
Expected: all `node --test` files pass, all Playwright specs pass.

- [ ] **Step 9: Commit**

```bash
git add mapper/src/colors.jsx mapper/src/styles.jsx mapper/src/main.jsx mapper/src/style.css mapper/test/map.spec.js
git commit -m "Add the four label color pickers to the style control"
```

---

### Task 4: Documentation

**Files:**
- Modify: `mapper/docs/user-manual.md:31-41`
- Modify: `mapper/docs/architecture.md:73-79`
- Modify: `mapper/docs/backlog.md:6-11`
- Delete: `mapper/docs/superpowers/specs/2026-09-08-mapper-label-colors-design.md`
- Delete: `mapper/docs/superpowers/plans/2026-09-08-mapper-label-colors.md`

**Model:** `haiku` — the replacement prose is given verbatim.

**Interfaces:**
- Consumes: the behavior built in Tasks 1-3.
- Produces: nothing code depends on.

- [ ] **Step 1: Add the pickers to the user manual**

In `mapper/docs/user-manual.md`, after the paragraph ending "falls back to 100% text and buildings from zoom 13." insert:

```markdown
Below the steppers, four color pickers set the label colors:

- **Places** covers town, city and country names.
- **Streets** covers street and road names.
- **POIs** covers points of interest and airport names.
- **Water** covers lake, sea and river names.

Picking a color recolors every label in that group and gives it a white or
black halo, whichever contrasts. The `×` beside a picker puts the group back to
the colors the style ships; it is greyed out while the group is unset, and an
unset picker shows the color the current style gives that group.

Not every style draws every group. Dark and Fiord carry no points of interest,
and only Liberty, Bright and Positron name airports. A picker for a group the
current style does not draw still works and is still remembered; it just
changes nothing on screen until you switch to a style that draws it.

The four colors apply to whichever style is showing and are saved to
`localStorage` under `mapper.colors`. A missing or unrecognised color leaves
that group on the style's own colors without disturbing the other three.
```

- [ ] **Step 2: Record the composition in architecture.md**

In `mapper/docs/architecture.md`, replace the paragraph beginning "`styles.jsx` holds the style as fetched, untransformed" (lines 73-79) with:

```markdown
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
to a detached element's `style.color` and reads `getComputedStyle` back, which
the browser normalises to `rgb(r, g, b)`. It needs a DOM, so it lives in
`colors.jsx` and Playwright covers it rather than `node --test`.
```

- [ ] **Step 3: Extend the per-style memory backlog item**

In `mapper/docs/backlog.md`, replace the first line of the per-style memory bullet:

```markdown
- Per-style memory of the Text and Buildings settings. One setting shared by
```

with:

```markdown
- Per-style memory of the Text, Buildings and label color settings. One setting
  shared by
```

- [ ] **Step 4: Verify the docs are accurate**

Run: `cd mapper && npm test`
Expected: all pass. Read the three edited documents once against the code to confirm every name, key and behavior they state matches what Tasks 1-3 built.

- [ ] **Step 5: Delete the spec and the plan and commit**

Working documents are deleted in the final commit before merge; the permanent docs above carry what mattered.

```bash
git rm mapper/docs/superpowers/specs/2026-09-08-mapper-label-colors-design.md mapper/docs/superpowers/plans/2026-09-08-mapper-label-colors.md
git add mapper/docs/user-manual.md mapper/docs/architecture.md mapper/docs/backlog.md
git commit -m "Document the label color pickers"
```
