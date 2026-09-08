import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  TWEAKS_KEY, TEXT_SCALES, BUILDING_ZOOMS, DEFAULT_TWEAKS,
  validateTweaks, parseTweaks, loadTweaks, saveTweaks, applyTweaks,
} from '../src/tweaks.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    raw: map,
  }
}

const BIG = { textScale: 1.5, buildingMinZoom: 15 }

function stub() {
  return {
    version: 8,
    name: 'stub',
    sources: {},
    layers: [
      { id: 'bg', type: 'background', paint: { 'background-color': '#fff' } },
      {
        id: 'plain-label',
        type: 'symbol',
        'source-layer': 'place',
        layout: { 'text-size': 12 },
      },
      {
        id: 'interp-label',
        type: 'symbol',
        'source-layer': 'place',
        layout: { 'text-size': ['interpolate', ['linear'], ['zoom'], 10, 10, 16, 20] },
      },
      { id: 'icon-only', type: 'symbol', 'source-layer': 'poi', layout: { 'icon-size': 1 } },
      { id: 'odd-label', type: 'symbol', 'source-layer': 'place', layout: { 'text-size': ['get', 'size'] } },
      { id: 'building', type: 'fill', 'source-layer': 'building', minzoom: 13, maxzoom: 14 },
      { id: 'building-3d', type: 'fill-extrusion', 'source-layer': 'building', minzoom: 14 },
      {
        id: 'building-label',
        type: 'symbol',
        'source-layer': 'building',
        minzoom: 13,
        layout: { 'text-size': 12 },
      },
      { id: 'road', type: 'line', 'source-layer': 'transportation', minzoom: 4 },
    ],
  }
}

const layer = (style, id) => style.layers.find((l) => l.id === id)

test('the notches and defaults are the listed ones', () => {
  assert.deepEqual(TEXT_SCALES, [1, 1.1, 1.2, 1.3, 1.4, 1.5])
  assert.deepEqual(BUILDING_ZOOMS, [13, 14, 15, 16, null])
  assert.deepEqual(DEFAULT_TWEAKS, { textScale: 1, buildingMinZoom: 13 })
  assert.deepEqual(validateTweaks(DEFAULT_TWEAKS), DEFAULT_TWEAKS)
})

test('a null buildingMinZoom (Off) validates and round-trips through the store and JSON', () => {
  const off = { textScale: 1, buildingMinZoom: null }
  assert.deepEqual(validateTweaks(off), off)
  const store = fakeStore()
  assert.deepEqual(saveTweaks(store, off), off)
  assert.deepEqual(loadTweaks(store), off)
  assert.deepEqual(parseTweaks(JSON.stringify(off)), off)
})

test('a saved tweaks value round-trips', () => {
  const store = fakeStore()
  assert.deepEqual(saveTweaks(store, BIG), BIG)
  assert.deepEqual(loadTweaks(store), BIG)
  assert.equal(store.raw.size, 1)
  assert.ok(store.raw.has(TWEAKS_KEY))
})

test('a missing key gives the default tweaks', () => {
  assert.deepEqual(loadTweaks(fakeStore()), DEFAULT_TWEAKS)
})

test('a malformed document gives the default tweaks', () => {
  assert.deepEqual(loadTweaks(fakeStore({ [TWEAKS_KEY]: '{not json' })), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks('[]'), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks('null'), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks(null), DEFAULT_TWEAKS)
})

test('an off-notch value or a missing field gives the default tweaks', () => {
  assert.deepEqual(parseTweaks(JSON.stringify({ textScale: 1.25, buildingMinZoom: 15 })), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks(JSON.stringify({ textScale: 1.2, buildingMinZoom: 12 })), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks(JSON.stringify({ textScale: 1.2 })), DEFAULT_TWEAKS)
  assert.deepEqual(parseTweaks(JSON.stringify({ textScale: '1.2', buildingMinZoom: 15 })), DEFAULT_TWEAKS)
  assert.equal(validateTweaks(null), null)
  assert.equal(validateTweaks(7), null)
})

test('saving an off-notch value writes nothing', () => {
  const store = fakeStore()
  assert.equal(saveTweaks(store, { textScale: 2, buildingMinZoom: 13 }), null)
  assert.equal(store.raw.size, 0)
})

test('a plain text-size scales', () => {
  const out = applyTweaks(stub(), BIG)
  assert.equal(layer(out, 'plain-label').layout['text-size'], 18)
})

test("an interpolate's outputs scale and its zoom stops do not", () => {
  const out = applyTweaks(stub(), BIG)
  assert.deepEqual(layer(out, 'interp-label').layout['text-size'],
    ['interpolate', ['linear'], ['zoom'], 10, 15, 16, 30])
})

test('an absent or unrecognised text-size is left alone', () => {
  const out = applyTweaks(stub(), BIG)
  assert.deepEqual(layer(out, 'icon-only'), layer(stub(), 'icon-only'))
  assert.deepEqual(layer(out, 'odd-label').layout['text-size'], ['get', 'size'])
})

test("a building layer's minzoom rises to the floor", () => {
  const out = applyTweaks(stub(), { textScale: 1, buildingMinZoom: 15 })
  assert.equal(layer(out, 'building-3d').minzoom, 15)
})

test('a symbol layer on the building source-layer gets both text scaling and the floor', () => {
  const out = applyTweaks(stub(), BIG)
  const label = layer(out, 'building-label')
  assert.equal(label.layout['text-size'], 18)
  assert.equal(label.minzoom, 15)
})

test('a building layer whose maxzoom is at or below the floor is dropped', () => {
  const out = applyTweaks(stub(), { textScale: 1, buildingMinZoom: 15 })
  assert.equal(layer(out, 'building'), undefined)
  const at = applyTweaks(stub(), { textScale: 1, buildingMinZoom: 14 })
  assert.equal(layer(at, 'building'), undefined)
})

test('a null floor (Off) drops every building layer', () => {
  const out = applyTweaks(stub(), { textScale: 1, buildingMinZoom: null })
  assert.equal(layer(out, 'building'), undefined)
  assert.equal(layer(out, 'building-3d'), undefined)
  assert.equal(layer(out, 'building-label'), undefined)
})

test('a non-building layer is untouched by the floor', () => {
  const out = applyTweaks(stub(), { textScale: 1, buildingMinZoom: 16 })
  assert.deepEqual(layer(out, 'road'), layer(stub(), 'road'))
})

test('a non-building layer is untouched when the floor is Off', () => {
  const out = applyTweaks(stub(), { textScale: 1, buildingMinZoom: null })
  assert.deepEqual(layer(out, 'road'), layer(stub(), 'road'))
})

test('the default tweaks leave a style alone', () => {
  assert.deepEqual(applyTweaks(stub(), DEFAULT_TWEAKS), stub())
})

test('the input style is not mutated', () => {
  const input = stub()
  const before = JSON.stringify(input)
  const out = applyTweaks(input, BIG)
  assert.equal(JSON.stringify(input), before)
  assert.notEqual(out, input)
  assert.notEqual(out.layers, input.layers)
})

test('applying twice to the same input does not compound', () => {
  const input = stub()
  const once = applyTweaks(input, BIG)
  const twice = applyTweaks(input, BIG)
  assert.deepEqual(twice, once)
})

test('off-notch tweaks fall back to the defaults inside the transform', () => {
  assert.deepEqual(applyTweaks(stub(), { textScale: 3, buildingMinZoom: 20 }), stub())
  assert.deepEqual(applyTweaks(stub(), null), stub())
})
