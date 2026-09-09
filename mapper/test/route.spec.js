import { test, expect } from './pw.js'
import { startPage, routeStyle } from './harness.js'
import { ROUTE_LAYER_ID } from '../src/route.js'

let server

test.beforeAll(async () => { server = await startPage() })
test.afterAll(async () => { await server.close() })

const GEOMETRY = { type: 'LineString', coordinates: [[-73.94, 42.81], [-73.93, 42.81], [-73.92, 42.82]] }

function orsResponse(distance = 1234, duration = 900) {
  return {
    type: 'FeatureCollection',
    features: [{
      type: 'Feature',
      geometry: GEOMETRY,
      properties: { segments: [{ distance, duration }] },
    }],
  }
}

const PLACES = [
  { id: 'a', name: 'Alpha', lat: 42.8142, lon: -73.9396, zoom: 12, bearing: 0 },
  { id: 'b', name: 'Bravo', lat: 42.8090, lon: -73.9310, zoom: 12, bearing: 0 },
  { id: 'c', name: 'Charlie', lat: 42.8200, lon: -73.9200, zoom: 12, bearing: 0 },
]

async function open(page, places = PLACES) {
  await routeStyle(page)
  await page.goto(server.url)
  await expect(page.locator('#map canvas')).toBeVisible()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await page.evaluate((p) => localStorage.setItem('mapper.places', JSON.stringify(p)), places)
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
}

const check = (name) => `#places-list li:has(.place-name:text-is("${name}")) .place-check`
const hasLayer = (page) => page.evaluate(
  (id) => window.mapper.map.getStyle().layers.some((l) => l.id === id), ROUTE_LAYER_ID)
const styleName = (page) => page.evaluate(() => window.mapper.map.getStyle().name)

test('selecting two places auto-draws the route with no button click', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) }))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await expect.poll(() => hasLayer(page)).toBe(true)
  await expect(page.locator('#route-summary')).toHaveText('1.2 km · 15 min')
})

test('the route layer is drawn dotted and blue', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) }))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await expect.poll(() => hasLayer(page)).toBe(true)
  const layer = await page.evaluate(
    (id) => window.mapper.map.getStyle().layers.find((l) => l.id === id), ROUTE_LAYER_ID)
  expect(layer.layout['line-cap']).toBe('round')
  expect(layer.paint['line-dasharray'][0]).toBe(0)
  expect(layer.paint['line-dasharray'][1]).toBeGreaterThan(0)
  expect(layer.paint['line-color']).toMatch(/^#[0-9a-f]{6}$/i)
})

test('list order, not selection order, sets the coordinate order sent to ORS', async ({ page }) => {
  await open(page)
  const requested = page.waitForRequest('**/192.168.1.169:8082/**')
  await page.route('**/192.168.1.169:8082/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) }))
  // Ticked out of list order (Alpha, Bravo, Charlie): if the request followed
  // tick order it would read Charlie, Alpha, Bravo instead.
  await page.check(check('Charlie'))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  const req = await requested
  const body = req.postDataJSON()
  expect(body.coordinates).toEqual([
    [-73.9396, 42.8142],
    [-73.931, 42.809],
    [-73.92, 42.82],
  ])
  await expect(page.locator('#places-list li:has(.place-name:text-is("Alpha")) .place-order')).toHaveText('1')
  await expect(page.locator('#places-list li:has(.place-name:text-is("Bravo")) .place-order')).toHaveText('2')
  await expect(page.locator('#places-list li:has(.place-name:text-is("Charlie")) .place-order')).toHaveText('3')
})

test('the order badges show each row its position in list order, not tick order', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) }))
  await page.check(check('Bravo'))
  await page.check(check('Alpha'))
  await expect(page.locator('#places-list li:has(.place-name:text-is("Alpha")) .place-order')).toHaveText('1')
  await expect(page.locator('#places-list li:has(.place-name:text-is("Bravo")) .place-order')).toHaveText('2')
})

test('reordering rows changes the coordinate order sent to ORS', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) }))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await page.check(check('Charlie'))
  await expect.poll(() => hasLayer(page)).toBe(true)

  const requested = page.waitForRequest('**/192.168.1.169:8082/**')
  await page.locator('#places-list li:has(.place-name:text-is("Charlie"))')
    .dragTo(page.locator('#places-list li:has(.place-name:text-is("Alpha"))'))
  const req = await requested
  expect(req.postDataJSON().coordinates).toEqual([
    [-73.92, 42.82],
    [-73.9396, 42.8142],
    [-73.931, 42.809],
  ])
  await expect(page.locator('#places-list li:has(.place-name:text-is("Charlie")) .place-order')).toHaveText('1')
  await expect(page.locator('#places-list li:has(.place-name:text-is("Alpha")) .place-order')).toHaveText('2')
  await expect(page.locator('#places-list li:has(.place-name:text-is("Bravo")) .place-order')).toHaveText('3')
})

test('deselecting down to one place clears the route', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) }))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await expect.poll(() => hasLayer(page)).toBe(true)
  await page.uncheck(check('Bravo'))
  await expect.poll(() => hasLayer(page)).toBe(false)
  await expect(page.locator('#route-info')).toHaveCount(0)
})

test('the Clear route button empties the selection and removes the line', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) }))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await expect.poll(() => hasLayer(page)).toBe(true)
  await page.click('#route-clear')
  await expect.poll(() => hasLayer(page)).toBe(false)
  await expect(page.locator(check('Alpha'))).not.toBeChecked()
  await expect(page.locator(check('Bravo'))).not.toBeChecked()
})

test('deleting a place that is in the route re-routes through what remains', async ({ page }) => {
  await open(page)
  let lastBody = null
  await page.route('**/192.168.1.169:8082/**', (r) => {
    lastBody = r.request().postDataJSON()
    return r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) })
  })
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await page.check(check('Charlie'))
  await expect.poll(() => hasLayer(page)).toBe(true)
  await page.click('#places-list li:has(.place-name:text-is("Bravo")) .place-del')
  await expect.poll(() => lastBody && lastBody.coordinates.length).toBe(2)
  expect(lastBody.coordinates).toEqual([[-73.9396, 42.8142], [-73.92, 42.82]])
  await expect.poll(() => hasLayer(page)).toBe(true)
})

test('the route survives a style switch, a stepper move and a color commit', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) }))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await expect.poll(() => hasLayer(page)).toBe(true)

  await page.click('#styles .style-button[data-style="dark"]')
  await expect.poll(() => styleName(page)).toBe('dark')
  await expect.poll(() => hasLayer(page)).toBe(true)

  await page.click('#styles .tweak-up[data-tweak="text"]')
  await expect.poll(() => hasLayer(page)).toBe(true)

  await page.locator('#styles .color-swatch[data-color="streets"]').fill('#1a1a1a')
  await expect.poll(() => hasLayer(page)).toBe(true)
})

test('a not-routable response shows its own toast', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) => r.fulfill({
    status: 404,
    contentType: 'application/json',
    body: JSON.stringify({ error: { code: 2010, message: 'Could not find routable point.' } }),
  }))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await expect(page.locator('#toast')).toHaveText(/Schenectady/)
  await expect.poll(() => hasLayer(page)).toBe(false)
})

test('an unreachable service shows its own toast, distinct from not-routable', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) => r.abort('connectionrefused'))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await expect(page.locator('#toast')).toHaveText(/local network/)
  await expect.poll(() => hasLayer(page)).toBe(false)
})

test('a route is not remembered across a reload', async ({ page }) => {
  await open(page)
  await page.route('**/192.168.1.169:8082/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(orsResponse()) }))
  await page.check(check('Alpha'))
  await page.check(check('Bravo'))
  await expect.poll(() => hasLayer(page)).toBe(true)
  await page.reload()
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
  await expect.poll(() => hasLayer(page)).toBe(false)
  await expect(page.locator(check('Alpha'))).not.toBeChecked()
})
