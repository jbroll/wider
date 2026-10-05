import fs from 'node:fs/promises'

import { test, expect } from './pw.js'
import { startPage, routeStyle } from './harness.js'

let server

test.beforeAll(async () => { server = await startPage() })
test.afterAll(async () => { await server.close() })

const SAVED = {
  'mapper.style': 'dark',
  'mapper.routePref': 'recommended',
  'mapper.tweaks': JSON.stringify({ textScale: 1.2, buildingMinZoom: 15 }),
  'mapper.pins': JSON.stringify({ scale: 1.5, iconScale: 1, text: '#000000', background: 'transparent' }),
  'mapper.places': JSON.stringify([
    { id: 'a1', name: 'Alpha', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0, icon: 'star', hidden: false, route: true },
    { id: 'b2', name: 'Bravo', lat: 45.75, lon: 4.85, zoom: 12, bearing: 0, icon: 'pin', hidden: true, route: false },
  ]),
}

const loaded = (page) => page.waitForFunction(() => window.mapper && window.mapper.map.loaded())

async function open(page, saved = {}) {
  await routeStyle(page)
  await page.goto(server.url)
  await page.evaluate((s) => {
    localStorage.clear()
    for (const [k, v] of Object.entries(s)) localStorage.setItem(k, v)
  }, saved)
  await page.reload()
  await loaded(page)
}

const storage = (page) => page.evaluate(() => {
  const out = {}
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i)
    if (k !== 'mapper.view') out[k] = localStorage.getItem(k)
  }
  return out
})

async function pick(page, name, body) {
  const chooser = page.waitForEvent('filechooser')
  await page.click('#import')
  await (await chooser).setFiles({ name, mimeType: 'application/json', buffer: Buffer.from(body) })
}

test('export, clear and import restores the saved data', async ({ page }) => {
  await open(page, SAVED)
  await expect(page.locator('#places-list .place-name')).toHaveText(['Alpha', 'Bravo'])
  const before = await storage(page)
  expect(before).toEqual(SAVED)

  const download = page.waitForEvent('download')
  await page.click('#export')
  const file = await download
  expect(file.suggestedFilename()).toMatch(/^mapper-\d{4}-\d{2}-\d{2}\.json$/)
  const text = await fs.readFile(await file.path(), 'utf8')
  const doc = JSON.parse(text)
  expect(doc.app).toBe('mapper')
  expect(doc.version).toBe(1)
  expect(doc.data['mapper.style']).toBe('dark')
  expect(doc.data['mapper.places'].map((p) => p.name)).toEqual(['Alpha', 'Bravo'])
  expect(doc.data['mapper.places'].map((p) => p.route)).toEqual([true, false])

  await open(page)
  await expect(page.locator('#places-list .place')).toHaveCount(0)
  expect(await storage(page)).toEqual({})

  let question = ''
  page.once('dialog', (d) => { question = d.message(); d.accept() })
  await pick(page, file.suggestedFilename(), text)

  await expect(page.locator('#toast')).toHaveText(/^Imported /)
  await loaded(page)
  expect(question).toContain('The page reloads afterwards.')
  expect(await storage(page)).toEqual(before)
  await expect(page.locator('#places-list .place-name')).toHaveText(['Alpha', 'Bravo'])
  await expect(page.locator('#places-list .place-check').nth(0)).toBeChecked()
  await expect(page.locator('#places-list .place-check').nth(1)).not.toBeChecked()
  await expect(page.locator('#styles .style-button.current')).toHaveText('Dark')
})

test('an invalid key is skipped and named in the message after the reload', async ({ page }) => {
  await open(page, { 'mapper.style': 'bright' })
  page.once('dialog', (d) => d.accept())
  await pick(page, 'mixed.json', JSON.stringify({
    app: 'mapper',
    version: 1,
    data: { 'mapper.style': 'positron', 'mapper.colors': 'red' },
  }))
  await expect(page.locator('#toast')).toHaveText('Imported map style. Skipped as invalid: label colors.')
  await loaded(page)
  expect(await storage(page)).toEqual({ 'mapper.style': 'positron' })
})

test('a file that is not a mapper export changes nothing and asks nothing', async ({ page }) => {
  await open(page, SAVED)
  let asked = false
  page.on('dialog', (d) => { asked = true; d.dismiss() })
  await pick(page, 'other.json', JSON.stringify({ app: 'other', version: 1, data: {} }))
  await expect(page.locator('#toast')).toHaveText('That file is not a mapper export.')
  await pick(page, 'broken.json', '{"app":')
  await expect(page.locator('#toast')).toHaveText('That file is not valid JSON.')
  expect(asked).toBe(false)
  expect(await storage(page)).toEqual(SAVED)
})

test('declining the confirmation changes nothing', async ({ page }) => {
  await open(page, SAVED)
  const dialog = page.waitForEvent('dialog')
  await pick(page, 'other.json', JSON.stringify({ app: 'mapper', version: 1, data: { 'mapper.style': 'fiord' } }))
  await (await dialog).dismiss()
  await expect(page.locator('#styles .style-button.current')).toHaveText('Dark')
  expect(await storage(page)).toEqual(SAVED)
})
