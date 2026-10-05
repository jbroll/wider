import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  APP, VERSION, KEYS, NOT_JSON, NOT_MAPPER,
  buildExport, exportName, parseImport, applyImport, confirmText, importedText, nothingText,
} from '../src/backup.js'
import { saveView } from '../src/view.js'
import { saveStyle } from '../src/styles.js'
import { saveTweaks } from '../src/tweaks.js'
import { saveColors } from '../src/colors.js'
import { savePins } from '../src/pins.js'
import { savePlaces } from '../src/places.js'
import { saveRoutePref, saveRouteSelected, loadRouteSelected, pruneSelected } from '../src/route.js'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')

function memoryStore(initial = {}) {
  const data = { ...initial }
  return {
    data,
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v) },
  }
}

const PARIS = { id: 'a1', name: 'Paris', lat: 48.8566, lon: 2.3522, zoom: 12, bearing: 0, icon: 'star', hidden: false }
const LYON = { id: 'b2', name: 'Lyon', lat: 45.75, lon: 4.85, zoom: 11, bearing: 90, icon: 'pin', hidden: true }

function fullStore() {
  const s = memoryStore()
  saveView(s, { center: [2.35, 48.85], zoom: 9, bearing: 30, pitch: 20 })
  saveStyle(s, 'dark')
  saveTweaks(s, { textScale: 1.3, buildingMinZoom: 15 })
  saveColors(s, { places: '#ff0000', streets: null, pois: '#00f', water: null })
  savePins(s, { scale: 1.2, iconScale: 0.7, text: '#000000', background: 'transparent' })
  savePlaces(s, [PARIS, LYON])
  saveRoutePref(s, 'recommended')
  saveRouteSelected(s, ['b2', 'a1'])
  return s
}

const fileFor = (data) => JSON.stringify({ app: APP, version: VERSION, exported: '2026-10-05T12:00:00.000Z', data })

test('KEYS lists every persisted key exported from src', () => {
  const declared = []
  for (const name of fs.readdirSync(path.join(ROOT, 'src'))) {
    if (!/\.jsx?$/.test(name)) continue
    const text = fs.readFileSync(path.join(ROOT, 'src', name), 'utf8')
    for (const m of text.matchAll(/export const \w+_KEY = '(mapper\.[^']+)'/g)) declared.push(m[1])
  }
  assert.deepEqual(KEYS.map((e) => e.key).sort(), declared.sort())
})

test('KEYS matches the Persistence table in docs/architecture.md, in order', () => {
  const doc = fs.readFileSync(path.join(ROOT, 'docs', 'architecture.md'), 'utf8')
  const section = doc.split('## Persistence')[1].split('\n## ')[0]
  const rows = [...section.matchAll(/^\| `(mapper\.[^`]+)` \|/gm)].map((m) => m[1])
  assert.deepEqual(KEYS.map((e) => e.key), rows)
})

test('an export carries the app, the version, the time and every set key as a parsed value', () => {
  const now = new Date('2026-10-05T12:34:56.000Z')
  const out = buildExport(fullStore(), now)
  assert.equal(out.app, 'mapper')
  assert.equal(out.version, 1)
  assert.equal(out.exported, '2026-10-05T12:34:56.000Z')
  assert.deepEqual(Object.keys(out.data), KEYS.map((e) => e.key))
  assert.equal(out.data['mapper.style'], 'dark')
  assert.equal(out.data['mapper.routePref'], 'recommended')
  assert.deepEqual(out.data['mapper.routeSelected'], ['b2', 'a1'])
  assert.deepEqual(out.data['mapper.places'], [PARIS, LYON])
  assert.deepEqual(out.data['mapper.tweaks'], { textScale: 1.3, buildingMinZoom: 15 })
})

test('an export leaves out keys that are not set', () => {
  const s = memoryStore()
  saveStyle(s, 'fiord')
  assert.deepEqual(buildExport(s).data, { 'mapper.style': 'fiord' })
})

test('an export leaves out a stored value that would load as its fallback', () => {
  const s = memoryStore({
    'mapper.view': '{not json',
    'mapper.style': 'nonesuch',
    'mapper.colors': '"red"',
    'mapper.routePref': 'recommended',
  })
  assert.deepEqual(buildExport(s).data, { 'mapper.routePref': 'recommended' })
})

test('the export file is named for the local date', () => {
  assert.equal(exportName(new Date(2026, 9, 5, 23, 59)), 'mapper-2026-10-05.json')
  assert.equal(exportName(new Date(2027, 0, 9, 0, 1)), 'mapper-2027-01-09.json')
})

test('export then import into an empty store reproduces every stored value', () => {
  const source = fullStore()
  const result = parseImport(JSON.stringify(buildExport(source)))
  assert.deepEqual(result.skipped, [])
  const target = memoryStore()
  applyImport(target, result.writes)
  assert.deepEqual(target.data, source.data)
})

test('a file that is not JSON is rejected whole', () => {
  assert.deepEqual(parseImport('{"app": "mapper",'), { error: NOT_JSON })
  assert.deepEqual(parseImport(''), { error: NOT_JSON })
})

test('a file that is not a mapper export is rejected whole', () => {
  assert.deepEqual(parseImport('[]'), { error: NOT_MAPPER })
  assert.deepEqual(parseImport('null'), { error: NOT_MAPPER })
  assert.deepEqual(parseImport('{"version": 1, "data": {}}'), { error: NOT_MAPPER })
  assert.deepEqual(parseImport('{"app": "other", "version": 1, "data": {}}'), { error: NOT_MAPPER })
  assert.deepEqual(parseImport('{"app": "mapper", "version": 1}'), { error: NOT_MAPPER })
  assert.deepEqual(parseImport('{"app": "mapper", "version": 1, "data": []}'), { error: NOT_MAPPER })
})

test('an unsupported version is rejected whole', () => {
  assert.deepEqual(parseImport('{"app": "mapper", "version": 2, "data": {}}'),
    { error: 'Unsupported mapper export version: 2.' })
  assert.deepEqual(parseImport('{"app": "mapper", "data": {}}'),
    { error: 'Unsupported mapper export version: null.' })
  assert.deepEqual(parseImport('{"app": "mapper", "version": "1", "data": {}}'),
    { error: 'Unsupported mapper export version: "1".' })
})

test('unknown keys are ignored', () => {
  const result = parseImport(fileFor({ 'mapper.style': 'bright', 'mapper.future': 1, other: 'x' }))
  assert.deepEqual(result.writes.map((w) => w.key), ['mapper.style'])
  assert.deepEqual(result.skipped, [])
})

test('a key whose value fails validation is skipped and the rest are written', () => {
  const result = parseImport(fileFor({
    'mapper.view': { center: [500, 0], zoom: 3, bearing: 0, pitch: 0 },
    'mapper.style': 'nonesuch',
    'mapper.tweaks': { textScale: 0.5, buildingMinZoom: 13 },
    'mapper.colors': 'red',
    'mapper.pins': [],
    'mapper.places': { id: 'a1' },
    'mapper.routePref': 'recommended',
    'mapper.routeSelected': 'a1',
  }))
  assert.deepEqual(result.writes, [{ key: 'mapper.routePref', label: 'route preference', raw: 'recommended' }])
  assert.deepEqual(result.skipped.map((s) => s.key), [
    'mapper.view', 'mapper.style', 'mapper.tweaks', 'mapper.colors', 'mapper.pins', 'mapper.places',
    'mapper.routeSelected',
  ])
})

test('inside a valid key, fields and entries are cleaned as on load', () => {
  const result = parseImport(fileFor({
    'mapper.colors': { places: '#123456', streets: 'red' },
    'mapper.places': [PARIS, { id: '', name: 'bad' }],
  }))
  const raw = Object.fromEntries(result.writes.map((w) => [w.key, JSON.parse(w.raw)]))
  assert.deepEqual(raw['mapper.colors'], { places: '#123456', streets: null, pois: null, water: null })
  assert.deepEqual(raw['mapper.places'], [PARIS])
  assert.deepEqual(result.skipped, [])
})

test('an imported selection naming no imported place is written, then pruned on load', () => {
  const result = parseImport(fileFor({ 'mapper.places': [PARIS], 'mapper.routeSelected': ['a1', 'zz', 7] }))
  assert.deepEqual(result.skipped, [])
  const target = memoryStore()
  applyImport(target, result.writes)
  assert.equal(target.data['mapper.routeSelected'], '["a1","zz"]')
  assert.deepEqual(pruneSelected(loadRouteSelected(target), [PARIS]), ['a1'])
  assert.deepEqual(pruneSelected(loadRouteSelected(target), [LYON]), [])
})

test('import replaces the keys it writes and leaves absent keys alone', () => {
  const target = fullStore()
  const before = { ...target.data }
  const result = parseImport(fileFor({ 'mapper.style': 'positron', 'mapper.places': [] }))
  applyImport(target, result.writes)
  assert.equal(target.data['mapper.style'], 'positron')
  assert.equal(target.data['mapper.places'], '[]')
  for (const key of ['mapper.view', 'mapper.tweaks', 'mapper.colors', 'mapper.pins', 'mapper.routePref', 'mapper.routeSelected']) {
    assert.equal(target.data[key], before[key])
  }
})

test('a bare-string key is stored as the string, not as JSON', () => {
  const target = memoryStore()
  applyImport(target, parseImport(fileFor({ 'mapper.style': 'dark' })).writes)
  assert.equal(target.data['mapper.style'], 'dark')
})

test('the messages name what is written and what is skipped', () => {
  const result = parseImport(fileFor({
    'mapper.places': [PARIS],
    'mapper.style': 'dark',
    'mapper.view': { center: [2, 48], zoom: 9, bearing: 0, pitch: 0 },
    'mapper.colors': 'red',
  }))
  assert.equal(confirmText(result, 'mapper-2026-10-05.json'),
    'Replace the saved view, map style and places with the ones in mapper-2026-10-05.json?' +
    ' Skipped as invalid: label colors. The page reloads afterwards.')
  assert.equal(importedText(result), 'Imported view, map style and places. Skipped as invalid: label colors.')
  const none = parseImport(fileFor({ 'mapper.colors': 'red', 'mapper.pins': 3 }))
  assert.equal(none.writes.length, 0)
  assert.equal(nothingText(none, 'x.json'), 'Nothing to import from x.json. Skipped as invalid: label colors and pin labels.')
})
