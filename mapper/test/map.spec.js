import { test, expect } from './pw.js'
import { startPage, routeStyle, styleFor, startDomHarness } from './harness.js'

let server
let domServer

test.beforeAll(async () => { server = await startPage() })
test.afterAll(async () => { await server.close() })
test.beforeAll(async () => { domServer = await startDomHarness() })
test.afterAll(async () => { await domServer.close() })

async function open(page) {
  await routeStyle(page)
  await page.goto(server.url)
  await expect(page.locator('#map canvas')).toBeVisible()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
}

const bearing = (page) => page.evaluate(() => window.mapper.map.getBearing())
const center = (page) => page.evaluate(() => window.mapper.map.getCenter().toArray())

test('the map fills the window', async ({ page }) => {
  await open(page)
  const box = await page.locator('#map canvas').boundingBox()
  const size = page.viewportSize()
  expect(box.width).toBeGreaterThan(size.width - 5)
  expect(box.height).toBeGreaterThan(size.height - 5)
})

test('the compass returns the map to north', async ({ page }) => {
  await open(page)
  await page.evaluate(() => window.mapper.map.setBearing(45))
  expect(await bearing(page)).toBeCloseTo(45, 1)
  await page.click('.maplibregl-ctrl-compass')
  await expect.poll(() => bearing(page)).toBe(0)
})

test('a right-click drops a pin and names it', async ({ page }) => {
  await open(page)
  const box = await page.locator('#map canvas').boundingBox()
  await page.mouse.click(box.width / 2, box.height / 2, { button: 'right' })
  await expect(page.locator('#pin-name')).toBeVisible()
  await page.fill('#pin-name', 'Middle')
  await page.press('#pin-name', 'Enter')
  await expect(page.locator('#places-list .place-name')).toHaveText(['Middle'])
})

test('escape discards the pin', async ({ page }) => {
  await open(page)
  const box = await page.locator('#map canvas').boundingBox()
  await page.mouse.click(box.width / 2, box.height / 2, { button: 'right' })
  await expect(page.locator('#pin-name')).toBeVisible()
  await page.press('#pin-name', 'Escape')
  await expect(page.locator('#pin-name')).toHaveCount(0)
  await expect(page.locator('#places-list .place')).toHaveCount(0)
})

test('a second right-click discards the first pending pin', async ({ page }) => {
  await open(page)
  const box = await page.locator('#map canvas').boundingBox()
  await page.mouse.click(box.width / 2, box.height / 2, { button: 'right' })
  await expect(page.locator('#pin-name')).toBeVisible()
  await page.mouse.click(box.width / 4, box.height / 4, { button: 'right' })
  await expect(page.locator('#pin-name')).toHaveCount(1)
  await expect(page.locator('.maplibregl-marker')).toHaveCount(1)
})

test('a right-drag rotates and drops no pin', async ({ page }) => {
  await open(page)
  const box = await page.locator('#map canvas').boundingBox()
  const x = box.width / 2
  const y = box.height / 2
  await page.mouse.move(x, y)
  await page.mouse.down({ button: 'right' })
  await page.mouse.move(x + 150, y, { steps: 12 })
  await page.mouse.up({ button: 'right' })
  expect(await bearing(page)).not.toBe(0)
  await expect(page.locator('#pin-name')).toHaveCount(0)
})

test('clicking a saved place moves the map to it', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.click('#places-list .place-name')
  await expect.poll(() => center(page).then(([lon]) => Math.round(lon))).toBe(2)
  const [lon, lat] = await center(page)
  expect(lat).toBeCloseTo(48.8566, 1)
  expect(lon).toBeCloseTo(2.3522, 1)
})

test('deleting a place removes it from the panel and storage', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.click('.place-del')
  await expect(page.locator('#places-list .place')).toHaveCount(0)
  const stored = await page.evaluate(() => localStorage.getItem('mapper.places'))
  expect(stored).not.toContain('a1')
})

test('dragging a row reorders the list, and the order survives a reload', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify([
      { id: 'a1', name: 'Alpha', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 },
      { id: 'b2', name: 'Bravo', lat: 45.75, lon: 4.85, zoom: 12, bearing: 0 },
    ]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await expect(page.locator('#places-list .place-name')).toHaveText(['Alpha', 'Bravo'])

  await page.locator('#places-list li:has(.place-name:text-is("Bravo"))')
    .dragTo(page.locator('#places-list li:has(.place-name:text-is("Alpha"))'))
  await expect(page.locator('#places-list .place-name')).toHaveText(['Bravo', 'Alpha'])

  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await expect(page.locator('#places-list .place-name')).toHaveText(['Bravo', 'Alpha'])
})

test('dragging a place past the last row moves it to the end, and the order survives a reload', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify([
      { id: 'a1', name: 'Alpha', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 },
      { id: 'b2', name: 'Bravo', lat: 45.75, lon: 4.85, zoom: 12, bearing: 0 },
      { id: 'c3', name: 'Charlie', lat: 41.9, lon: 12.5, zoom: 12, bearing: 0 },
    ]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await expect(page.locator('#places-list .place-name')).toHaveText(['Alpha', 'Bravo', 'Charlie'])

  await page.locator('#places-list li:has(.place-name:text-is("Alpha"))')
    .dragTo(page.locator('#places-list .place-dropzone'))
  await expect(page.locator('#places-list .place-name')).toHaveText(['Bravo', 'Charlie', 'Alpha'])

  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await expect(page.locator('#places-list .place-name')).toHaveText(['Bravo', 'Charlie', 'Alpha'])
})

test('a named place gets a marker showing its name', async ({ page }) => {
  await open(page)
  const box = await page.locator('#map canvas').boundingBox()
  await page.mouse.click(box.width / 2, box.height / 2, { button: 'right' })
  await expect(page.locator('#pin-name')).toBeVisible()
  await page.fill('#pin-name', 'Middle')
  await page.press('#pin-name', 'Enter')
  await expect(page.locator('.place-label')).toHaveText('Middle')
})

test('the marker splits a pin at the coordinate from a non-interactive label', async ({ page }) => {
  await open(page)
  const box = await page.locator('#map canvas').boundingBox()
  await page.mouse.click(box.width / 2, box.height / 2, { button: 'right' })
  await page.fill('#pin-name', 'Middle')
  await page.press('#pin-name', 'Enter')
  await expect(page.locator('.place-marker svg')).toHaveCount(1)
  await expect(page.locator('.place-marker .place-label')).toHaveText('Middle')
  expect(await page.locator('.place-label').evaluate((el) => getComputedStyle(el).pointerEvents)).toBe('none')
})

test('a saved-place marker uses the same icon as the pending pin', async ({ page }) => {
  await open(page)
  const box = await page.locator('#map canvas').boundingBox()
  await page.mouse.click(box.width / 2, box.height / 2, { button: 'right' })
  await expect(page.locator('#pin-name')).toBeVisible()
  const pendingSvg = await page.locator('.maplibregl-marker svg').innerHTML()
  await page.fill('#pin-name', 'Middle')
  await page.press('#pin-name', 'Enter')
  const savedSvg = await page.locator('.place-marker svg').innerHTML()
  expect(savedSvg).toBe(pendingSvg)
})

// MapLibre's default marker anchors 'center' with offset [0, -14] (see
// maplibre-gl's Marker constructor), placing the SVG teardrop's tip - not
// the element's own box - at the coordinate.
const DEFAULT_MARKER_OFFSET = { x: 0, y: -14 }

async function markerAnchor(page, selector) {
  return page.evaluate(([sel, offset]) => {
    const map = window.mapper.map
    const canvas = map.getCanvasContainer().getBoundingClientRect()
    const rect = document.querySelector(sel).getBoundingClientRect()
    return {
      x: rect.left + rect.width / 2 - canvas.left - offset.x,
      y: rect.top + rect.height / 2 - canvas.top - offset.y,
    }
  }, [selector, DEFAULT_MARKER_OFFSET])
}

test('a saved-place marker anchors on its stored coordinate, before and after panning and zooming', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())

  const checkAnchor = async () => {
    const projected = await page.evaluate(() => window.mapper.map.project([2.3522, 48.8566]))
    const anchor = await markerAnchor(page, '.place-marker')
    expect(Math.abs(anchor.x - projected.x)).toBeLessThanOrEqual(2)
    expect(Math.abs(anchor.y - projected.y)).toBeLessThanOrEqual(2)
  }

  await checkAnchor()
  await page.evaluate(() => window.mapper.map.jumpTo({ center: [10, 30], zoom: 6, bearing: 20 }))
  await checkAnchor()
})

test('deleting a place removes its marker', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await expect(page.locator('.place-marker')).toHaveCount(1)
  await page.click('.place-del')
  await expect(page.locator('.place-marker')).toHaveCount(0)
})

test('a place marker survives a style switch', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.click('#styles .style-button[data-style="dark"]')
  await expect.poll(() => page.evaluate(() => window.mapper.map.getStyle().name)).toBe('dark')
  await expect(page.locator('.place-marker')).toHaveCount(1)
  await expect(page.locator('.place-label')).toHaveText('Paris')
})

test('clicking a place marker moves the map', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.click('.place-marker')
  await expect.poll(() => center(page).then(([lon]) => Math.round(lon))).toBe(2)
  const [lon, lat] = await center(page)
  expect(lat).toBeCloseTo(48.8566, 1)
  expect(lon).toBeCloseTo(2.3522, 1)
})

async function dragPin(page, name, dx, dy) {
  const pin = page.locator(`.place-marker:has(.place-label:text-is("${name}"))`)
  const box = await pin.boundingBox()
  const x = box.x + box.width / 2
  const y = box.y + box.height / 2
  await page.mouse.move(x, y)
  await page.mouse.down()
  await page.mouse.move(x + dx, y + dy, { steps: 8 })
  await page.mouse.up()
}

test('dragging a marker moves the place, persists it, and refetches the route through the new point', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify([
      { id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 },
      { id: 'b2', name: 'Lyon', lat: 45.75, lon: 4.85, zoom: 12, bearing: 0 },
    ]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.evaluate(() => window.mapper.map.jumpTo({ center: [2.3522, 48.8566], zoom: 10 }))
  await page.check('#places-list li:has(.place-name:text-is("Paris")) .place-check')
  await page.check('#places-list li:has(.place-name:text-is("Lyon")) .place-check')
  let requestCount = 0
  let lastBody = null
  await page.route('**/192.168.1.169:8082/**', (r) => {
    requestCount += 1
    lastBody = r.request().postDataJSON()
    return r.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          geometry: { type: 'LineString', coordinates: [[2.35, 48.85], [4.85, 45.75]] },
          properties: { segments: [{ distance: 100, duration: 60 }] },
        }],
      }),
    })
  })
  await expect.poll(() => requestCount).toBeGreaterThan(0)
  const before = requestCount

  await dragPin(page, 'Paris', 60, 40)

  const stored = await page.evaluate(
    () => JSON.parse(localStorage.getItem('mapper.places')).find((p) => p.id === 'a1'))
  expect(stored.lat).not.toBeCloseTo(48.8566, 3)
  expect(stored.lon).not.toBeCloseTo(2.3522, 3)

  await expect.poll(() => requestCount).toBeGreaterThan(before)
  expect(lastBody.coordinates[0][0]).toBeCloseTo(stored.lon, 3)
  expect(lastBody.coordinates[0][1]).toBeCloseTo(stored.lat, 3)
})

test('a marker drag does not fly the map', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.evaluate(() => window.mapper.map.jumpTo({ center: [2.3522, 48.8566], zoom: 10 }))
  await page.evaluate(() => {
    window.__flyToCalls = 0
    const map = window.mapper.map
    const orig = map.flyTo.bind(map)
    map.flyTo = (...args) => { window.__flyToCalls += 1; return orig(...args) }
  })
  await dragPin(page, 'Paris', 60, 40)
  expect(await page.evaluate(() => window.__flyToCalls)).toBe(0)
})

test("an existing marker follows its place when it moves", async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.evaluate(() => window.mapper.map.jumpTo({ center: [2.3522, 48.8566], zoom: 10 }))
  const before = await page.locator('.place-marker').evaluate((el) => el.style.transform)
  await dragPin(page, 'Paris', 60, 40)
  await expect(page.locator('.place-marker')).toHaveCount(1)
  await expect.poll(() => page.locator('.place-marker').evaluate((el) => el.style.transform)).not.toBe(before)
})

test('a reload restores the last view', async ({ page }) => {
  await open(page)
  await page.evaluate(() => window.mapper.map.jumpTo({ center: [2.3522, 48.8566], zoom: 12 }))
  await expect.poll(() => page.evaluate(() => localStorage.getItem('mapper.view'))).toContain('2.35')
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  const [lon, lat] = await center(page)
  expect(lon).toBeCloseTo(2.3522, 2)
  expect(lat).toBeCloseTo(48.8566, 2)
  expect(await page.evaluate(() => window.mapper.map.getZoom())).toBeCloseTo(12, 2)
})

test('the panel collapses and expands', async ({ page }) => {
  await open(page)
  await page.click('#places-toggle')
  await expect(page.locator('#places-body')).toHaveCount(0)
  await page.click('#places-toggle')
  await expect(page.locator('#places-body')).toBeVisible()
})

test('a style load failure shows the failure message', async ({ page }) => {
  await page.route('**/tiles.openfreemap.org/**', (r) => r.fulfill({ status: 500 }))
  await page.goto(server.url)
  await expect(page.locator('#map')).toHaveText(/style failed to load/)
})

test('a style body MapLibre rejects after construction shows the failure message', async ({ page }) => {
  const style = {
    version: 8,
    name: 'broken',
    sources: {},
    layers: [{ id: 'missing-source', type: 'fill', source: 'nonexistent' }],
  }
  await page.route('**/tiles.openfreemap.org/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(style) }))
  await page.goto(server.url)
  await expect(page.locator('#map')).toHaveText(/style failed to load/)
})

test('a failed tile leaves a drawn map in place', async ({ page }) => {
  const style = {
    version: 8,
    name: 'test-with-source',
    sources: {
      raster: {
        type: 'raster',
        tiles: ['https://tiles.openfreemap.org/data/{z}/{x}/{y}.png'],
        tileSize: 256,
      },
    },
    layers: [{ id: 'bg', type: 'raster', source: 'raster' }],
  }
  await page.route('**/tiles.openfreemap.org/styles/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(style) }))
  await page.route('**/tiles.openfreemap.org/data/**', (r) => r.abort('failed'))
  const tileFailed = page.waitForEvent('requestfailed', (req) => req.url().includes('/data/'))
  await page.goto(server.url)
  await expect(page.locator('#map canvas')).toBeVisible()
  await tileFailed
  await expect(page.locator('#map canvas')).toBeVisible()
  await expect(page.locator('#map')).not.toHaveText(/style failed to load/)
})

const styleName = (page) => page.evaluate(() => window.mapper.map.getStyle().name)

// styledata (win or lose) fires from Style.update() on the next render frame
// after setStyle, so one animation frame is enough for a losing switch to
// have had its chance to apply.
const nextFrame = (page) => page.evaluate(() => new Promise((r) => requestAnimationFrame(() => r())))

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

test('the view, a saved place and a pending pin survive a switch', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    localStorage.setItem('mapper.places', JSON.stringify(
      [{ id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0 }]))
  })
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.evaluate(() => window.mapper.map.jumpTo({ center: [2.3522, 48.8566], zoom: 12 }))
  const box = await page.locator('#map canvas').boundingBox()
  await page.mouse.click(box.width / 3, box.height / 3, { button: 'right' })
  await expect(page.locator('#pin-name')).toBeVisible()
  await page.fill('#pin-name', 'Half typed')
  await page.click('#styles .style-button[data-style="positron"]')
  await expect.poll(() => styleName(page)).toBe('positron')
  const [lon, lat] = await center(page)
  expect(lon).toBeCloseTo(2.3522, 2)
  expect(lat).toBeCloseTo(48.8566, 2)
  expect(await page.evaluate(() => window.mapper.map.getZoom())).toBeCloseTo(12, 2)
  await expect(page.locator('#places-list .place-name')).toHaveText(['Paris'])
  await expect(page.locator('#pin-name')).toHaveValue('Half typed')
  // One marker for the pending pin, one for the saved place.
  await expect(page.locator('.maplibregl-marker')).toHaveCount(2)
  await expect(page.locator('.place-label')).toHaveText('Paris')
})

test('a later click wins over a slower in-flight switch', async ({ page }) => {
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
  await page.click('#styles .style-button[data-style="fiord"]')
  await expect.poll(() => styleName(page)).toBe('fiord')
  const darkResponded = page.waitForResponse('**/tiles.openfreemap.org/styles/dark')
  releaseDark()
  await darkResponded
  await nextFrame(page)
  expect(await styleName(page)).toBe('fiord')
  await expect(page.locator('#styles .style-button.current')).toHaveAttribute('data-style', 'fiord')
  expect(await page.evaluate(() => localStorage.getItem('mapper.style'))).toBe('fiord')
})

test('clicking back to the current style cancels an in-flight switch', async ({ page }) => {
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
  await page.click('#styles .style-button[data-style="liberty"]')
  const darkResponded = page.waitForResponse('**/tiles.openfreemap.org/styles/dark')
  releaseDark()
  await darkResponded
  await nextFrame(page)
  expect(await styleName(page)).toBe('liberty')
  await expect(page.locator('#styles .style-button.current')).toHaveAttribute('data-style', 'liberty')
  expect(await page.evaluate(() => localStorage.getItem('mapper.style'))).toBe(null)
})

test('a failed style request keeps the current style and shows a toast', async ({ page }) => {
  await open(page)
  // Registered after routeStyle, so it wins for this one path.
  await page.route('**/tiles.openfreemap.org/styles/dark', (r) => r.fulfill({ status: 500 }))
  await page.click('#styles .style-button[data-style="dark"]')
  await expect(page.locator('#toast')).toHaveText('Could not load the Dark style.')
  expect(await styleName(page)).toBe('liberty')
  await expect(page.locator('#styles .style-button.current')).toHaveAttribute('data-style', 'liberty')
  expect(await page.evaluate(() => localStorage.getItem('mapper.style'))).toBe(null)
  await expect(page.locator('#map')).not.toHaveText(/style failed to load/)
})

const textSize = (page, id) => page.evaluate(
  (layerId) => window.mapper.map.getStyle().layers.find((l) => l.id === layerId).layout['text-size'], id)

const minZoom = (page, id) => page.evaluate(
  (layerId) => window.mapper.map.getStyle().layers.find((l) => l.id === layerId).minzoom, id)

const hasLayer = (page, id) => page.evaluate(
  (layerId) => window.mapper.map.getStyle().layers.some((l) => l.id === layerId), id)

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

test('stepping Text to the top reads 200% and disables the up button', async ({ page }) => {
  await open(page)
  for (let i = 0; i < 10; i += 1) await page.click(up('text'))
  await expect(page.locator(reading('text'))).toHaveText('200%')
  await expect(page.locator(up('text'))).toBeDisabled()
})

test('stepping Text up grows a saved-place marker', async ({ page }) => {
  await open(page)
  const box = await page.locator('#map canvas').boundingBox()
  await page.mouse.click(box.width / 2, box.height / 2, { button: 'right' })
  await page.fill('#pin-name', 'Middle')
  await page.press('#pin-name', 'Enter')
  await expect(page.locator('.place-label')).toHaveText('Middle')
  const before = await page.locator('.place-label').evaluate((el) => getComputedStyle(el).fontSize)
  await page.click(up('text'))
  await expect.poll(() =>
    page.locator('.place-label').evaluate((el) => getComputedStyle(el).fontSize)).not.toBe(before)
  const after = await page.locator('.place-label').evaluate((el) => getComputedStyle(el).fontSize)
  expect(parseFloat(after)).toBeGreaterThan(parseFloat(before))
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
  for (let i = 0; i < 10; i += 1) await page.click(up('text'))
  await expect(page.locator(reading('text'))).toHaveText('200%')
  await expect(page.locator(up('text'))).toBeDisabled()
  await expect(page.locator(down('text'))).toBeEnabled()
  for (let i = 0; i < 4; i += 1) await page.click(up('buildings'))
  await expect(page.locator(reading('buildings'))).toHaveText('Off')
  await expect(page.locator(up('buildings'))).toBeDisabled()
})

test('stepping Buildings to Off removes the building layer', async ({ page }) => {
  await open(page)
  for (let i = 0; i < 4; i += 1) await page.click(up('buildings'))
  await expect(page.locator(reading('buildings'))).toHaveText('Off')
  await expect.poll(() => hasLayer(page, 'building')).toBe(false)
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

test('a stepper moved during an in-flight switch is carried by that switch', async ({ page }) => {
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
  await page.click(up('text'))
  releaseDark()
  await expect.poll(() => styleName(page)).toBe('dark')
  await expect.poll(() => textSize(page, 'place-label')).toBeCloseTo(13.2, 5)
})

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

test('dragging the swatch coalesces map updates to one per frame and defers the store write to commit', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    window.__setStyleCalls = 0
    const map = window.mapper.map
    const orig = map.setStyle.bind(map)
    map.setStyle = (...args) => { window.__setStyleCalls += 1; return orig(...args) }
    const el = document.querySelector('#styles .color-swatch[data-color="streets"]')
    for (const v of ['#111111', '#222222', '#333333']) {
      el.value = v
      el.dispatchEvent(new Event('input', { bubbles: true }))
    }
  })
  expect(await page.evaluate(() => localStorage.getItem('mapper.colors'))).toBe(null)
  await expect.poll(() => paintOf(page, 'street-label', 'text-color')).toBe('#333333')
  expect(await page.evaluate(() => window.__setStyleCalls)).toBe(1)
  await page.evaluate(() => {
    const el = document.querySelector('#styles .color-swatch[data-color="streets"]')
    el.dispatchEvent(new Event('change', { bubbles: true }))
  })
  await expect.poll(() => page.evaluate(() => localStorage.getItem('mapper.colors')))
    .toContain('333333')
})

// The spec above dispatches its events in one synchronous task, so no frame
// can land between them; this one spans real animation frames, which a
// coalescing guard deleted from previewColors would fail to survive.
test('coalescing still holds when input events land in separate frames', async ({ page }) => {
  await open(page)
  await page.evaluate(() => {
    window.__setStyleCalls = 0
    const map = window.mapper.map
    const orig = map.setStyle.bind(map)
    map.setStyle = (...args) => { window.__setStyleCalls += 1; return orig(...args) }
  })
  const dispatch = (sel, values) => page.evaluate(([s, vals]) => {
    const el = document.querySelector(s)
    for (const v of vals) {
      el.value = v
      el.dispatchEvent(new Event('input', { bubbles: true }))
    }
  }, [sel, values])
  const sel = swatch('streets')
  await dispatch(sel, ['#111111', '#222222'])
  await nextFrame(page)
  await dispatch(sel, ['#333333'])
  await nextFrame(page)
  expect(await page.evaluate(() => window.__setStyleCalls)).toBeLessThan(3)
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

test('a picker for a group absent from the style still renders, stores and clears', async ({ page }) => {
  await open(page)
  await page.click('#styles .style-button[data-style="fiord"]')
  await expect.poll(() => styleName(page)).toBe('fiord')
  await expect(page.locator(swatch('pois'))).toHaveValue('#000000')
  await expect(page.locator(clearer('pois'))).toBeDisabled()
  await page.locator(swatch('pois')).fill('#7a4f00')
  await expect.poll(() => page.evaluate(() => localStorage.getItem('mapper.colors')))
    .toContain('7a4f00')
  await expect(page.locator(clearer('pois'))).toBeEnabled()
})

test('toHex returns null for an unset color and for one it cannot reduce to rgb', async ({ page }) => {
  await page.goto(domServer.url)
  expect(await page.evaluate(() => window.__colorsDom.toHex(''))).toBeNull()
  // lab() is valid CSS the browser keeps in lab() form rather than
  // normalizing to rgb(), so the regex in toHex never matches it.
  expect(await page.evaluate(() => window.__colorsDom.toHex('lab(50% 40 59.5)'))).toBeNull()
  expect(await page.evaluate(() => window.__colorsDom.toHex('#334455'))).toBe('#334455')
})

test('forSwatch expands a stored #rgb value to #rrggbb', async ({ page }) => {
  await page.goto(domServer.url)
  expect(await page.evaluate(() => window.__colorsDom.forSwatch('#abc'))).toBe('#aabbcc')
  expect(await page.evaluate(() => window.__colorsDom.forSwatch('#334455'))).toBe('#334455')
})

test('seedColors falls back to black when the only color for a group is unparseable', async ({ page }) => {
  await page.goto(domServer.url)
  const out = await page.evaluate(() => window.__colorsDom.seedColors({
    version: 8,
    layers: [{
      id: 'place-label',
      type: 'symbol',
      'source-layer': 'place',
      paint: { 'text-color': 'lab(50% 40 59.5)' },
    }],
  }))
  expect(out.places).toBe('#000000')
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
