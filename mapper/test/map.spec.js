import { test, expect } from './pw.js'
import { startPage, routeStyle } from './harness.js'

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
