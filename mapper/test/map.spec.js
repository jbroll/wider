import { test, expect } from './pw.js'
import { startPage, routeStyle, styleFor } from './harness.js'

let server

test.beforeAll(async () => { server = await startPage() })
test.afterAll(async () => { await server.close() })

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
  await expect(page.locator('.maplibregl-marker')).toHaveCount(1)
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
