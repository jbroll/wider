# mapper style switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a five-button control that switches the map between the five OpenFreeMap styles and remembers the choice across launches.

**Architecture:** A pure `src/styles.js` holds the style table and the localStorage load/save/lookup, in the same shape as `view.js` and `places.js`, so it tests under `node --test`. A MapLibre custom control at `top-right` hosts Preact-rendered buttons; a switch fetches the style JSON first and only calls `map.setStyle` on success, so a failed fetch leaves the running map alone and raises a toast instead. Startup still hands MapLibre a style URL, so the existing style-load failure path is untouched.

**Tech Stack:** Node 22, esbuild, MapLibre GL 5, Preact 10 with `@preact/signals`, `node --test`, Playwright.

## Global Constraints

- All work happens in `/home/john/src/wider/mapper`. Paths below are relative to it.
- The five style ids and URLs are exactly:
  - `liberty` → `https://tiles.openfreemap.org/styles/liberty`
  - `bright` → `https://tiles.openfreemap.org/styles/bright`
  - `positron` → `https://tiles.openfreemap.org/styles/positron`
  - `dark` → `https://tiles.openfreemap.org/styles/dark`
  - `fiord` → `https://tiles.openfreemap.org/styles/fiord`
  There is no `3d` style. Do not add one.
- `liberty` is the default. An unknown, missing or malformed stored id falls back to it.
- The localStorage key is `mapper.style`, its own key beside `mapper.view` and `mapper.places`.
- Pure modules take a `localStorage`-shaped store as an argument. They never touch `window`.
- Unit test command: `node --test test/<file>.test.js`. Browser test command: `npx playwright test`.
- Full gate: `npm test` (runs `node --test test/*.test.js && playwright test`).
- Docs change in the same commit as the code they describe.
- Never open a pull request. Leave the work on the current branch.

---

### Task 1: The pure styles module

**Files:**
- Create: `src/styles.js`
- Test: `test/styles.test.js`

**Model:** `haiku` — the complete code and tests are given verbatim below.

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `STYLE_KEY: string` — `'mapper.style'`
  - `DEFAULT_STYLE_ID: string` — `'liberty'`
  - `STYLES: Array<{ id: string, name: string, url: string }>` — the five styles in display order
  - `validateStyleId(value: unknown): string | null`
  - `styleUrl(id: unknown): string` — URL for a valid id, else the default's URL
  - `loadStyle(store): string` — a valid id, always
  - `saveStyle(store, id): string | null` — writes and returns the id, or writes nothing and returns `null`

- [ ] **Step 1: Write the failing test**

Create `test/styles.test.js`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  STYLE_KEY, DEFAULT_STYLE_ID, STYLES, validateStyleId, styleUrl, loadStyle, saveStyle,
} from '../src/styles.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    raw: map,
  }
}

test('the five styles are listed and each resolves to a URL', () => {
  assert.deepEqual(STYLES.map((s) => s.id), ['liberty', 'bright', 'positron', 'dark', 'fiord'])
  for (const s of STYLES) {
    assert.equal(styleUrl(s.id), s.url)
    assert.equal(s.url, 'https://tiles.openfreemap.org/styles/' + s.id)
    assert.ok(s.name.length > 0)
  }
})

test('liberty is the default and is itself a listed style', () => {
  assert.equal(DEFAULT_STYLE_ID, 'liberty')
  assert.equal(validateStyleId(DEFAULT_STYLE_ID), DEFAULT_STYLE_ID)
})

test('a saved style round-trips', () => {
  const store = fakeStore()
  assert.equal(saveStyle(store, 'dark'), 'dark')
  assert.equal(loadStyle(store), 'dark')
  assert.equal(store.raw.size, 1)
  assert.ok(store.raw.has(STYLE_KEY))
})

test('a missing key gives the default style', () => {
  assert.equal(loadStyle(fakeStore()), DEFAULT_STYLE_ID)
})

test('an unknown id gives the default style', () => {
  assert.equal(loadStyle(fakeStore({ [STYLE_KEY]: '3d' })), DEFAULT_STYLE_ID)
  assert.equal(validateStyleId('3d'), null)
  assert.equal(styleUrl('3d'), styleUrl(DEFAULT_STYLE_ID))
})

test('a malformed value gives the default style', () => {
  assert.equal(loadStyle(fakeStore({ [STYLE_KEY]: '' })), DEFAULT_STYLE_ID)
  assert.equal(loadStyle(fakeStore({ [STYLE_KEY]: '{"id":"dark"}' })), DEFAULT_STYLE_ID)
  assert.equal(validateStyleId(null), null)
  assert.equal(validateStyleId(7), null)
  assert.equal(validateStyleId({ id: 'dark' }), null)
  assert.equal(styleUrl(undefined), styleUrl(DEFAULT_STYLE_ID))
})

test('saving an invalid id writes nothing', () => {
  const store = fakeStore()
  assert.equal(saveStyle(store, 'nope'), null)
  assert.equal(store.raw.size, 0)
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test test/styles.test.js`
Expected: FAIL, cannot find module `../src/styles.js`.

- [ ] **Step 3: Write the implementation**

Create `src/styles.js`:

```js
export const STYLE_KEY = 'mapper.style'

export const STYLES = ['liberty', 'bright', 'positron', 'dark', 'fiord'].map((id) => ({
  id,
  name: id[0].toUpperCase() + id.slice(1),
  url: 'https://tiles.openfreemap.org/styles/' + id,
}))

export const DEFAULT_STYLE_ID = 'liberty'

export function validateStyleId(value) {
  if (typeof value !== 'string') return null
  return STYLES.some((s) => s.id === value) ? value : null
}

export function styleUrl(id) {
  const wanted = validateStyleId(id) || DEFAULT_STYLE_ID
  return STYLES.find((s) => s.id === wanted).url
}

export function loadStyle(store) {
  return validateStyleId(store.getItem(STYLE_KEY)) || DEFAULT_STYLE_ID
}

export function saveStyle(store, id) {
  const clean = validateStyleId(id)
  if (clean) store.setItem(STYLE_KEY, clean)
  return clean
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `node --test test/styles.test.js`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add src/styles.js test/styles.test.js
git commit -m "Add the pure style table and its stored-id validation"
```

---

### Task 2: createMap takes a style URL

**Files:**
- Modify: `src/map.js:3-16`
- Modify: `src/main.jsx:1-16`
- Test: `test/map.spec.js` (existing specs must keep passing; no new specs here)

**Model:** `haiku` — two small edits given verbatim.

**Interfaces:**
- Consumes: `styleUrl(id)` and `loadStyle(store)` from Task 1.
- Produces: `createMap(container, view, style)` where `style` is a style URL string. The exported `STYLE_URL` constant is gone; `src/styles.js` owns the URLs now.

- [ ] **Step 1: Replace the hardcoded style in `src/map.js`**

Replace the whole file with:

```js
import maplibregl from 'maplibre-gl'

export function createMap(container, view, style) {
  const map = new maplibregl.Map({
    container,
    style,
    center: view.center,
    zoom: view.zoom,
    bearing: view.bearing,
    pitch: view.pitch,
    attributionControl: { compact: true },
  })
  map.addControl(new maplibregl.NavigationControl({ showCompass: true, visualizePitch: true }), 'top-right')
  return map
}
```

- [ ] **Step 2: Pass the saved style from `src/main.jsx`**

Add the import beneath the existing `./view.js` import:

```jsx
import { loadStyle, styleUrl } from './styles.js'
```

and change the `createMap` call inside the `try` block from

```jsx
    map = createMap(container, loadView(store))
```

to

```jsx
    map = createMap(container, loadView(store), styleUrl(loadStyle(store)))
```

- [ ] **Step 3: Confirm nothing else referenced `STYLE_URL`**

Run: `grep -rn "STYLE_URL" src test build.js serve.js`
Expected: no output. If anything matches, replace it with `styleUrl(...)` from `src/styles.js`.

- [ ] **Step 4: Run the full gate**

Run: `npm test`
Expected: PASS. The unit tests are unchanged and every existing Playwright spec still passes, because the default id resolves to the same Liberty URL that was hardcoded.

- [ ] **Step 5: Commit**

```bash
git add src/map.js src/main.jsx
git commit -m "Take the map style as an argument instead of hardcoding it"
```

---

### Task 3: The control, the toast, and switching

**Files:**
- Create: `src/styles.jsx`
- Modify: `src/main.jsx` (add the control after `attach(map)`)
- Modify: `src/style.css` (append rules)

**Model:** `sonnet` — three coordinated files and MapLibre/Preact integration.

**Interfaces:**
- Consumes: `STYLES`, `styleUrl`, `loadStyle`, `saveStyle` from Task 1; `store` from `src/store.js`.
- Produces:
  - `addStyleControl(map, store): void` — creates the toast host, renders it, and adds the control at `top-right`.
  - `switchStyle(map, store, id): Promise<boolean>` — fetches then switches; resolves `false` and toasts on failure.
  - DOM contract the Playwright specs in Task 4 depend on: the control element is `#styles`; each button is `button.style-button` with `data-style="<id>"`; the current one also carries class `current` and `aria-pressed="true"`; the toast is `#toast`.

- [ ] **Step 1: Write `src/styles.jsx`**

```jsx
import { render } from 'preact'
import { signal } from '@preact/signals'

import { STYLES, DEFAULT_STYLE_ID, loadStyle, saveStyle, styleUrl } from './styles.js'

const TOAST_MS = 4000

const current = signal(DEFAULT_STYLE_ID)
const message = signal('')

let timer = 0

export function toast(text) {
  message.value = text
  clearTimeout(timer)
  timer = setTimeout(() => { message.value = '' }, TOAST_MS)
}

// Fetch before setStyle: a failed request must not tear down the running map.
export async function switchStyle(map, store, id) {
  if (id === current.value) return true
  let style
  try {
    const res = await fetch(styleUrl(id))
    if (!res.ok) throw new Error('HTTP ' + res.status)
    style = await res.json()
  } catch (err) {
    console.error(err)
    toast('Could not load the ' + id + ' style.')
    return false
  }
  map.setStyle(style)
  current.value = id
  saveStyle(store, id)
  return true
}

function Buttons({ map, store }) {
  return STYLES.map((s) => (
    <button
      key={s.id}
      class={'style-button' + (current.value === s.id ? ' current' : '')}
      data-style={s.id}
      aria-pressed={current.value === s.id}
      title={s.name + ' map style'}
      onClick={() => switchStyle(map, store, s.id)}
    >
      {s.name}
    </button>
  ))
}

function Toast() {
  return message.value ? <div id="toast">{message.value}</div> : null
}

export function addStyleControl(map, store) {
  current.value = loadStyle(store)

  const host = document.createElement('div')
  document.body.appendChild(host)
  render(<Toast />, host)

  map.addControl({
    onAdd() {
      const el = document.createElement('div')
      el.id = 'styles'
      el.className = 'maplibregl-ctrl maplibregl-ctrl-group'
      render(<Buttons map={map} store={store} />, el)
      return el
    },
    onRemove() {},
  }, 'top-right')
}
```

- [ ] **Step 2: Add the control in `src/main.jsx`**

Add the import beside the other `./styles` import so the file reads:

```jsx
import { loadStyle, styleUrl } from './styles.js'
import { addStyleControl } from './styles.jsx'
```

and add the call directly after the existing `attach(map)` line, before the `render(<Places .../>)` line:

```jsx
  addStyleControl(map, store)
```

- [ ] **Step 3: Append the CSS to `src/style.css`**

`.maplibregl-ctrl-group button` is a 29×29 icon square by default, so the text buttons need their own width and padding.

```css
#styles {
  clear: both;
}

#styles .style-button {
  display: block;
  width: auto;
  min-width: 5.5rem;
  height: auto;
  padding: 4px 8px;
  border: 0;
  background: none;
  color: #111;
  font: inherit;
  text-align: left;
  cursor: pointer;
}

#styles .style-button:hover {
  background: rgba(0, 0, 0, 0.07);
}

#styles .style-button.current {
  font-weight: 600;
  background: rgba(0, 0, 0, 0.12);
}

#toast {
  position: absolute;
  bottom: 24px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 2;
  padding: 6px 12px;
  border-radius: 4px;
  background: rgba(0, 0, 0, 0.82);
  color: #fff;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.4);
}
```

- [ ] **Step 4: Verify the build and the existing specs**

Run: `npm test`
Expected: PASS. The new control renders inside the existing `top-right` stack, so the compass spec still finds `.maplibregl-ctrl-compass`.

- [ ] **Step 5: Check the control by eye**

Run: `npm start`
Expected: a stacked group of five labelled buttons below the navigation controls at the top right, with Liberty marked. Click Dark and the map redraws dark, the marked button moves, and the view holds. Close the window when done.

- [ ] **Step 6: Commit**

```bash
git add src/styles.jsx src/main.jsx src/style.css
git commit -m "Add the style control, the toast, and fetch-before-switch"
```

---

### Task 4: Per-style test stubs and the browser specs

**Files:**
- Modify: `test/harness.js:22-32`
- Modify: `test/map.spec.js` (append four specs)

**Model:** `sonnet` — Playwright route ordering and async map assertions need judgment.

**Interfaces:**
- Consumes: the DOM contract from Task 3 (`#styles`, `button.style-button[data-style]`, `.current`, `#toast`), and `window.mapper.map`.
- Produces: `styleFor(id)` and `STYLE_COLORS` exported from `test/harness.js`; `routeStyle(page)` keeps its existing signature and still answers every `tiles.openfreemap.org` path.

- [ ] **Step 1: Give the harness a per-style stub**

In `test/harness.js`, replace the `STYLE` constant and `routeStyle` (lines 22-32) with:

```js
// One background layer and no sources, so the map builds and paints without a
// single tile request leaving the machine. The colour and name differ per style
// so a test can tell which one is drawn.
export const STYLE_COLORS = {
  liberty: '#cfe8cf',
  bright: '#f6f0d8',
  positron: '#f4f4f4',
  dark: '#222222',
  fiord: '#4a5568',
}

export function styleFor(id) {
  return {
    version: 8,
    name: id,
    sources: {},
    layers: [{ id: 'bg', type: 'background', paint: { 'background-color': STYLE_COLORS[id] || '#cfe8cf' } }],
  }
}

export const STYLE = styleFor('liberty')

export async function routeStyle(page) {
  await page.route('**/tiles.openfreemap.org/**', (r) => {
    const id = new URL(r.request().url()).pathname.split('/').pop()
    const body = STYLE_COLORS[id] ? styleFor(id) : STYLE
    return r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) })
  })
}
```

`STYLE` stays exported: `test/map.spec.js` may still reference it, and keeping the name avoids touching specs this task does not own.

- [ ] **Step 2: Run the existing specs against the new stub**

Run: `npx playwright test`
Expected: PASS, unchanged. The default style is still `liberty`, which still returns the same `#cfe8cf` background.

- [ ] **Step 3: Write the four failing specs**

Append to `test/map.spec.js`:

```js
const styleName = (page) => page.evaluate(() => window.mapper.map.getStyle().name)

test('clicking a style loads it and marks its button', async ({ page }) => {
  await open(page)
  const asked = page.waitForRequest('**/tiles.openfreemap.org/styles/dark')
  await page.click('#styles .style-button[data-style="dark"]')
  await asked
  await expect.poll(() => styleName(page)).toBe('dark')
  await expect(page.locator('#styles .style-button.current')).toHaveAttribute('data-style', 'dark')
})

test('a reload comes back on the chosen style', async ({ page }) => {
  await open(page)
  await page.click('#styles .style-button[data-style="fiord"]')
  await expect.poll(() => styleName(page)).toBe('fiord')
  await expect.poll(() => page.evaluate(() => localStorage.getItem('mapper.style'))).toBe('fiord')
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  expect(await styleName(page)).toBe('fiord')
  await expect(page.locator('#styles .style-button.current')).toHaveAttribute('data-style', 'fiord')
})

test('the view and a saved place survive a switch', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.evaluate(() => window.mapper.map.jumpTo({ center: [2.3522, 48.8566], zoom: 12 }))
  await page.click('#styles .style-button[data-style="positron"]')
  await expect.poll(() => styleName(page)).toBe('positron')
  const [lon, lat] = await center(page)
  expect(lon).toBeCloseTo(2.3522, 2)
  expect(lat).toBeCloseTo(48.8566, 2)
  expect(await page.evaluate(() => window.mapper.map.getZoom())).toBeCloseTo(12, 2)
  await expect(page.locator('#places-list .place-name')).toHaveText(['Paris'])
})

test('a failed style request keeps the current style and shows a toast', async ({ page }) => {
  await open(page)
  // Registered after routeStyle, so it wins for this one path.
  await page.route('**/tiles.openfreemap.org/styles/dark', (r) => r.fulfill({ status: 500 }))
  await page.click('#styles .style-button[data-style="dark"]')
  await expect(page.locator('#toast')).toHaveText(/dark/)
  expect(await styleName(page)).toBe('liberty')
  await expect(page.locator('#styles .style-button.current')).toHaveAttribute('data-style', 'liberty')
  expect(await page.evaluate(() => localStorage.getItem('mapper.style'))).toBe(null)
  await expect(page.locator('#map')).not.toHaveText(/style failed to load/)
})
```

- [ ] **Step 4: Run them**

Run: `npx playwright test`
Expected: PASS, all specs.

If the last spec sees a leftover `mapper.style` from an earlier test, the specs are sharing storage: each Playwright test gets a fresh context, so this should not happen. If it does, assert `styleName` and the marked button only, and drop the `localStorage` line rather than adding cleanup.

- [ ] **Step 5: Run the full gate**

Run: `npm test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add test/harness.js test/map.spec.js
git commit -m "Stub each style separately and cover switching in the browser"
```

---

### Task 5: Documentation and backlog

**Files:**
- Modify: `docs/user-manual.md`
- Modify: `docs/architecture.md:47-52`
- Modify: `docs/backlog.md`
- Delete: `docs/superpowers/specs/2026-09-08-mapper-styles-design.md`
- Delete: `docs/superpowers/plans/2026-09-08-mapper-styles.md`

**Model:** `haiku` — the prose is given verbatim.

**Interfaces:**
- Consumes: the behavior built in Tasks 1-4.
- Produces: nothing code depends on.

- [ ] **Step 1: Document the control in `docs/user-manual.md`**

Insert this section between `## View persistence` and `## Saved places`:

```markdown
## Map style

The button group below the navigation controls at the top right picks the
map style: Liberty, Bright, Positron, Dark, or Fiord. The current one is
marked. The choice is saved to `localStorage` under `mapper.style` and is
restored on the next launch; a missing or unrecognised value falls back to
Liberty.

Switching fetches the new style before applying it, so a style that will
not load leaves the map as it is and shows a short-lived message at the
bottom of the window instead. The centre, zoom, bearing, saved places and a
half-typed pin all survive a switch.
```

Then extend the last paragraph of `## No WebGL` so it reads:

```markdown
If the map style itself fails to load, the map area instead shows "This
window cannot draw the map: the map style failed to load." A single failed
tile during panning or zooming does not trigger this; the map keeps working,
and neither does a style that fails when switched from the style buttons.
```

- [ ] **Step 2: Update `docs/architecture.md`**

Add to the `## UI` section, after the `window.mapper.map` paragraph:

```markdown
`src/styles.js` holds the style table and the stored-id validation, pure
and store-argument-taking like `view.js` and `places.js`. `src/styles.jsx`
is a MapLibre custom control: MapLibre decides where it sits in the
`top-right` stack and gives it `.maplibregl-ctrl-group`, and Preact renders
the buttons into the element `onAdd` returns.

A switch fetches the style JSON and only then calls `map.setStyle` with the
parsed object. A failed fetch never reaches `setStyle`, so the running map
stays up and the stored id and the marked button stay on the style that is
actually drawn. Startup still passes MapLibre a style URL, which keeps a
launch-time failure on the existing `map.on('error')` path.
```

Then replace the `## Why openfreemap Liberty` section with:

```markdown
## Why openfreemap

The styles come from `https://tiles.openfreemap.org/styles/`: vector tiles,
no API key, whole-planet coverage, and labels that stay upright under
rotation. Liberty is the default. OpenFreeMap's site also names a "3D"
style, but `/styles/3d` is a 404, so mapper offers the five that answer.
```

- [ ] **Step 3: Update `docs/backlog.md`**

Remove the `- Style switching.` line and add these two entries:

```markdown
- A control for how much the map draws when zoomed out, and per-style memory
  of such overrides. What a style shows at a given zoom is mostly its own
  zoom-interpolated opacity and label collision, which a zoom-range override
  cannot reach, and beneath that the tiles have hard floors: buildings only
  exist from zoom 13, POIs from 11, road labels from 6. Choosing a style that
  draws more is the lever that works.
- The vector source ends at zoom 14, so a close-up past that is magnified z14
  data rather than more detail.
```

- [ ] **Step 4: Verify the gate one more time**

Run: `npm test`
Expected: PASS.

- [ ] **Step 5: Commit the docs and delete the working documents**

```bash
git rm docs/superpowers/specs/2026-09-08-mapper-styles-design.md docs/superpowers/plans/2026-09-08-mapper-styles.md
git add docs/user-manual.md docs/architecture.md docs/backlog.md
git commit -m "Document style switching and retire the design spec"
```
