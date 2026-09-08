import { test } from 'node:test'
import assert from 'node:assert/strict'

import { VIEW_KEY, DEFAULT_VIEW, validateView, parseView, loadView, saveView } from '../src/view.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    raw: map,
  }
}

const PARIS = { center: [2.3522, 48.8566], zoom: 12.5, bearing: 30, pitch: 45 }

test('a saved view round-trips', () => {
  const store = fakeStore()
  saveView(store, PARIS)
  assert.deepEqual(loadView(store), PARIS)
  assert.equal(store.raw.size, 1)
  assert.ok(store.raw.has(VIEW_KEY))
})

test('a missing key gives the default view', () => {
  assert.deepEqual(loadView(fakeStore()), DEFAULT_VIEW)
})

test('malformed JSON gives the default view', () => {
  assert.deepEqual(loadView(fakeStore({ [VIEW_KEY]: '{not json' })), DEFAULT_VIEW)
  assert.deepEqual(parseView('[]'), DEFAULT_VIEW)
  assert.deepEqual(parseView('null'), DEFAULT_VIEW)
  assert.deepEqual(parseView(null), DEFAULT_VIEW)
})

test('out-of-range coordinates give the default view', () => {
  assert.deepEqual(parseView(JSON.stringify({ ...PARIS, center: [200, 48] })), DEFAULT_VIEW)
  assert.deepEqual(parseView(JSON.stringify({ ...PARIS, center: [2, 91] })), DEFAULT_VIEW)
  assert.deepEqual(parseView(JSON.stringify({ ...PARIS, center: [2] })), DEFAULT_VIEW)
  assert.deepEqual(parseView(JSON.stringify({ ...PARIS, center: '2,48' })), DEFAULT_VIEW)
})

test('out-of-range zoom and pitch give the default view', () => {
  assert.deepEqual(parseView(JSON.stringify({ ...PARIS, zoom: 40 })), DEFAULT_VIEW)
  assert.deepEqual(parseView(JSON.stringify({ ...PARIS, zoom: -1 })), DEFAULT_VIEW)
  assert.deepEqual(parseView(JSON.stringify({ ...PARIS, pitch: 90 })), DEFAULT_VIEW)
  assert.deepEqual(parseView(JSON.stringify({ ...PARIS, zoom: Number.NaN })), DEFAULT_VIEW)
})

test('a missing field gives the default view', () => {
  const { pitch, ...noPitch } = PARIS
  assert.deepEqual(parseView(JSON.stringify(noPitch)), DEFAULT_VIEW)
})

test('bearing is normalized into a single turn', () => {
  assert.equal(validateView({ ...PARIS, bearing: -90 }).bearing, 270)
  assert.equal(validateView({ ...PARIS, bearing: 0 }).bearing, 0)
  assert.equal(validateView({ ...PARIS, bearing: 720 }), null)
})

test('saving an invalid view writes nothing', () => {
  const store = fakeStore()
  assert.equal(saveView(store, { center: [0, 0] }), null)
  assert.equal(store.raw.size, 0)
})

test('the default view is itself valid', () => {
  assert.deepEqual(validateView(DEFAULT_VIEW), DEFAULT_VIEW)
})
