import { test, expect } from './pw.js'
import { startPage, routeStyle } from './harness.js'

let server

test.beforeAll(async () => { server = await startPage() })
test.afterAll(async () => { await server.close() })

const GEOCODE = '**/geocode/v1/autocomplete**'
const TOKEN = '0123456789abcdef0123456789abcdef'

const RESULTS = [
  { label: '120 State ST, Schenectady, NY', layer: 'address', coordinates: [-73.9473, 42.8151] },
  { label: 'State ST, Albany, NY', layer: 'street', coordinates: [-73.7562, 42.6526] },
]

function geocodeResponse(results = RESULTS) {
  return {
    type: 'FeatureCollection',
    features: results.map(({ label, layer, coordinates }) => ({
      type: 'Feature',
      geometry: { type: 'Point', coordinates },
      properties: { label, layer },
    })),
  }
}

const fulfill = (results) => (r) =>
  r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(geocodeResponse(results)) })

// Reduced motion makes MapLibre's flyTo a jump, so the test reads the
// destination without waiting out the animation.
async function open(page, search = '') {
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await routeStyle(page)
  await page.goto(server.url + search)
  await page.waitForFunction(() => window.mapper && window.mapper.map.loaded())
}

const view = (page) => page.evaluate(() => {
  const m = window.mapper.map
  return { lon: m.getCenter().lng, lat: m.getCenter().lat, zoom: m.getZoom() }
})

const options = (page) => page.locator('#search-results [role="option"]')

test('typing three characters lists the geocoder results', async ({ page }) => {
  await open(page)
  await page.route(GEOCODE, fulfill())
  await page.fill('#search', 'sta')
  await expect(options(page)).toHaveText(RESULTS.map((r) => r.label))
})

test('the request goes to geocode/ under the page path with the text', async ({ page }) => {
  await open(page)
  const requested = page.waitForRequest(GEOCODE)
  await page.route(GEOCODE, fulfill())
  await page.fill('#search', '120 state')
  const url = new URL((await requested).url())
  expect(url.origin + url.pathname).toBe(new URL('geocode/v1/autocomplete', server.url).href)
  expect(url.searchParams.get('text')).toBe('120 state')
  expect(url.searchParams.get('token')).toBeNull()
})

test('the page token is forwarded on the geocoder request', async ({ page }) => {
  await open(page, `?lang=fr&token=${TOKEN}`)
  const requested = page.waitForRequest(GEOCODE)
  await page.route(GEOCODE, fulfill())
  await page.fill('#search', 'state')
  const url = new URL((await requested).url())
  expect(url.searchParams.get('token')).toBe(TOKEN)
  expect(url.searchParams.get('lang')).toBeNull()
})

test('fewer than three characters sends no request', async ({ page }) => {
  await open(page)
  let count = 0
  await page.route(GEOCODE, (r) => { count++; return fulfill()(r) })
  await page.fill('#search', 'st')
  await page.waitForTimeout(600)
  expect(count).toBe(0)
  await expect(page.locator('#search-results')).toHaveCount(0)
})

test('typing a word one key at a time sends one request', async ({ page }) => {
  await open(page)
  let count = 0
  await page.route(GEOCODE, (r) => { count++; return fulfill()(r) })
  await page.locator('#search').pressSequentially('schenectady', { delay: 30 })
  await expect(options(page)).toHaveCount(2)
  await page.waitForTimeout(400)
  expect(count).toBe(1)
})

test('clicking a result flies the map there and closes the list', async ({ page }) => {
  await open(page)
  await page.route(GEOCODE, fulfill())
  await page.fill('#search', 'state')
  await options(page).first().click()
  await expect(page.locator('#search-results')).toHaveCount(0)
  await expect(page.locator('#search')).toHaveValue(RESULTS[0].label)
  await expect.poll(() => view(page)).toEqual({ lon: expect.closeTo(-73.9473, 4), lat: expect.closeTo(42.8151, 4), zoom: 17 })
})

test('arrow keys and Enter pick a result, with the zoom set by its layer', async ({ page }) => {
  await open(page)
  await page.route(GEOCODE, fulfill())
  await page.fill('#search', 'state')
  await expect(options(page)).toHaveCount(2)
  await page.press('#search', 'ArrowDown')
  await page.press('#search', 'ArrowDown')
  await expect(options(page).nth(1)).toHaveAttribute('aria-selected', 'true')
  await page.press('#search', 'Enter')
  await expect(page.locator('#search-results')).toHaveCount(0)
  await expect.poll(() => view(page)).toEqual({ lon: expect.closeTo(-73.7562, 4), lat: expect.closeTo(42.6526, 4), zoom: 15 })
})

test('Enter with nothing highlighted picks the first result', async ({ page }) => {
  await open(page)
  await page.route(GEOCODE, fulfill())
  await page.fill('#search', 'state')
  await expect(options(page)).toHaveCount(2)
  await page.press('#search', 'Enter')
  await expect.poll(() => view(page)).toEqual({ lon: expect.closeTo(-73.9473, 4), lat: expect.closeTo(42.8151, 4), zoom: 17 })
})

test('Escape closes the list without moving the map', async ({ page }) => {
  await open(page)
  await page.route(GEOCODE, fulfill())
  const before = await view(page)
  await page.fill('#search', 'state')
  await expect(options(page)).toHaveCount(2)
  await page.press('#search', 'Escape')
  await expect(page.locator('#search-results')).toHaveCount(0)
  expect(await view(page)).toEqual(before)
})

test('no matches says so', async ({ page }) => {
  await open(page)
  await page.route(GEOCODE, fulfill([]))
  await page.fill('#search', 'zzzz')
  await expect(page.locator('#search-results')).toHaveText('No matches')
})

test('an unreachable geocoder shows a toast', async ({ page }) => {
  await open(page)
  await page.route(GEOCODE, (r) => r.abort('connectionrefused'))
  await page.fill('#search', 'state')
  await expect(page.locator('#toast')).toHaveText('Could not reach the geocoder.')
  await expect(page.locator('#search-results')).toHaveCount(0)
})

test('a slow earlier response does not replace a later one', async ({ page }) => {
  await open(page)
  await page.route(GEOCODE, async (r) => {
    const text = new URL(r.request().url()).searchParams.get('text')
    if (text === 'albany') {
      await new Promise((resolve) => setTimeout(resolve, 800))
      return fulfill([RESULTS[1]])(r)
    }
    return fulfill([RESULTS[0]])(r)
  })
  await page.fill('#search', 'albany')
  await page.waitForTimeout(400)
  await page.fill('#search', 'schenectady')
  await expect(options(page)).toHaveText([RESULTS[0].label])
  await page.waitForTimeout(800)
  await expect(options(page)).toHaveText([RESULTS[0].label])
})

test('a search saves nothing but the view', async ({ page }) => {
  await open(page)
  await page.route(GEOCODE, fulfill())
  await page.fill('#search', 'state')
  await options(page).first().click()
  await expect.poll(() => page.evaluate(() => localStorage.getItem('mapper.view'))).not.toBeNull()
  const keys = await page.evaluate(() => Object.keys(localStorage))
  expect(keys).toEqual(['mapper.view'])
})
