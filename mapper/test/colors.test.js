import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  COLORS_KEY, GROUPS, DEFAULT_COLORS,
  validateColor, validateColors, parseColors, loadColors, saveColors,
  luminance, haloFor, applyColors,
} from '../src/colors.js'
import { applyTweaks } from '../src/tweaks.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    raw: map,
  }
}

function stub() {
  return {
    version: 8,
    name: 'stub',
    sources: {},
    layers: [
      { id: 'bg', type: 'background', paint: { 'background-color': '#fff' } },
      {
        id: 'place-label',
        type: 'symbol',
        'source-layer': 'place',
        paint: { 'text-color': '#333', 'text-halo-color': '#fff', 'text-halo-width': 1.4 },
      },
      {
        id: 'street-label',
        type: 'symbol',
        'source-layer': 'transportation_name',
        paint: { 'text-color': '#666' },
      },
      {
        id: 'street-shield',
        type: 'symbol',
        'source-layer': 'transportation_name',
        paint: { 'icon-opacity': 1 },
      },
      {
        id: 'poi-label',
        type: 'symbol',
        'source-layer': 'poi',
        paint: { 'text-color': '#666', 'text-halo-width': 1, 'icon-color': '#900' },
      },
      {
        id: 'airport-label',
        type: 'symbol',
        'source-layer': 'aerodrome_label',
        paint: { 'text-color': '#666', 'text-halo-width': 1 },
      },
      {
        id: 'water-label',
        type: 'symbol',
        'source-layer': 'water_name',
        paint: { 'text-color': '#495e91', 'text-halo-width': 1 },
      },
      {
        id: 'river-label',
        type: 'symbol',
        'source-layer': 'waterway',
        paint: { 'text-color': '#74aee9', 'text-halo-width': 1 },
      },
      { id: 'building', type: 'fill', 'source-layer': 'building', paint: { 'fill-color': '#ddd' } },
      { id: 'road', type: 'line', 'source-layer': 'transportation', paint: { 'line-color': '#eee' } },
    ],
  }
}

const layer = (style, id) => style.layers.find((l) => l.id === id)

const SET = { places: '#1a1a1a', streets: null, pois: '#7a4f00', water: null }

test('the groups are the four listed ones', () => {
  assert.deepEqual(GROUPS.map((g) => g.id), ['places', 'streets', 'pois', 'water'])
  assert.deepEqual(GROUPS.map((g) => g.label), ['Places', 'Streets', 'POIs', 'Water'])
  assert.deepEqual(GROUPS.map((g) => g.sourceLayers), [
    ['place'], ['transportation_name'], ['poi', 'aerodrome_label'], ['water_name', 'waterway'],
  ])
  assert.deepEqual(DEFAULT_COLORS, { places: null, streets: null, pois: null, water: null })
})

test('a color is #rgb or #rrggbb, case-insensitive', () => {
  assert.equal(validateColor('#abc'), '#abc')
  assert.equal(validateColor('#A1B2C3'), '#A1B2C3')
  assert.equal(validateColor('#1a1a1a'), '#1a1a1a')
  assert.equal(validateColor('red'), null)
  assert.equal(validateColor('#12345'), null)
  assert.equal(validateColor('rgb(1,2,3)'), null)
  assert.equal(validateColor(7), null)
  assert.equal(validateColor(null), null)
})

test('a saved colors value round-trips', () => {
  const store = fakeStore()
  assert.deepEqual(saveColors(store, SET), SET)
  assert.deepEqual(loadColors(store), SET)
  assert.equal(store.raw.size, 1)
  assert.ok(store.raw.has(COLORS_KEY))
})

test('a missing key gives all four groups unset', () => {
  assert.deepEqual(loadColors(fakeStore()), DEFAULT_COLORS)
})

test('a malformed document gives all four groups unset', () => {
  assert.deepEqual(loadColors(fakeStore({ [COLORS_KEY]: '{not json' })), DEFAULT_COLORS)
  assert.deepEqual(parseColors('[]'), DEFAULT_COLORS)
  assert.deepEqual(parseColors('null'), DEFAULT_COLORS)
  assert.deepEqual(parseColors(null), DEFAULT_COLORS)
})

test('a bad value in one group leaves the other three standing', () => {
  const raw = JSON.stringify({ places: '#1a1a1a', streets: 'blue', pois: 12, water: '#0f0' })
  assert.deepEqual(parseColors(raw), {
    places: '#1a1a1a', streets: null, pois: null, water: '#0f0',
  })
})

test('an unknown key is dropped and a missing one is null', () => {
  assert.deepEqual(validateColors({ places: '#000', bogus: '#fff' }), {
    places: '#000', streets: null, pois: null, water: null,
  })
})

test('the halo flips at the luminance threshold', () => {
  assert.equal(haloFor('#000000'), '#ffffff')
  assert.equal(haloFor('#ffffff'), '#000000')
  assert.ok(luminance('#bababa') < 0.5)
  assert.ok(luminance('#bcbcbc') >= 0.5)
  assert.equal(haloFor('#bababa'), '#ffffff')
  assert.equal(haloFor('#bcbcbc'), '#000000')
  assert.equal(haloFor('#fff'), '#000000')
})

test('a group recolors its own source-layers and no others', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, pois: '#7a4f00' })
  assert.equal(layer(out, 'poi-label').paint['text-color'], '#7a4f00')
  assert.equal(layer(out, 'airport-label').paint['text-color'], '#7a4f00')
  assert.equal(layer(out, 'place-label').paint['text-color'], '#333')
  assert.equal(layer(out, 'street-label').paint['text-color'], '#666')
  assert.equal(layer(out, 'water-label').paint['text-color'], '#495e91')
  assert.equal(layer(out, 'river-label').paint['text-color'], '#74aee9')
})

test('Water covers both water_name and waterway', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, water: '#0088ff' })
  assert.equal(layer(out, 'water-label').paint['text-color'], '#0088ff')
  assert.equal(layer(out, 'river-label').paint['text-color'], '#0088ff')
})

test('a layer with no text-color is left alone', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, streets: '#1a1a1a' })
  assert.deepEqual(layer(out, 'street-shield'), layer(stub(), 'street-shield'))
  assert.deepEqual(layer(out, 'road'), layer(stub(), 'road'))
  assert.deepEqual(layer(out, 'building'), layer(stub(), 'building'))
  assert.deepEqual(layer(out, 'bg'), layer(stub(), 'bg'))
})

test('the halo color follows the chosen color', () => {
  const dark = applyColors(stub(), { ...DEFAULT_COLORS, places: '#1a1a1a' })
  assert.equal(layer(dark, 'place-label').paint['text-halo-color'], '#ffffff')
  const light = applyColors(stub(), { ...DEFAULT_COLORS, places: '#eeeeee' })
  assert.equal(layer(light, 'place-label').paint['text-halo-color'], '#000000')
})

test('an absent halo width becomes 1 and an existing one survives', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, places: '#1a1a1a', streets: '#1a1a1a' })
  assert.equal(layer(out, 'street-label').paint['text-halo-width'], 1)
  assert.equal(layer(out, 'place-label').paint['text-halo-width'], 1.4)
})

test('icon-color is not touched', () => {
  const out = applyColors(stub(), { ...DEFAULT_COLORS, pois: '#7a4f00' })
  assert.equal(layer(out, 'poi-label').paint['icon-color'], '#900')
})

test('a null or malformed group leaves that group alone', () => {
  const out = applyColors(stub(), { places: '#1a1a1a', streets: 'blue', pois: null, water: undefined })
  assert.equal(layer(out, 'place-label').paint['text-color'], '#1a1a1a')
  assert.deepEqual(layer(out, 'street-label'), layer(stub(), 'street-label'))
  assert.deepEqual(layer(out, 'poi-label'), layer(stub(), 'poi-label'))
  assert.deepEqual(layer(out, 'water-label'), layer(stub(), 'water-label'))
})

test('the default colors leave a style alone', () => {
  assert.deepEqual(applyColors(stub(), DEFAULT_COLORS), stub())
  assert.deepEqual(applyColors(stub(), null), stub())
  assert.deepEqual(applyColors(stub(), 'nonsense'), stub())
})

test('the input style is not mutated', () => {
  const input = stub()
  const before = JSON.stringify(input)
  const out = applyColors(input, SET)
  assert.equal(JSON.stringify(input), before)
  assert.notEqual(out, input)
  assert.notEqual(out.layers, input.layers)
})

test('applying twice to the same input does not compound', () => {
  const once = applyColors(stub(), SET)
  const twice = applyColors(once, SET)
  assert.deepEqual(twice, once)
})

test('a style with no layers is returned as it is', () => {
  assert.equal(applyColors(null, SET), null)
  assert.deepEqual(applyColors({ version: 8 }, SET), { version: 8 })
})

test('a text-scale tweak and a label color survive one transform together', () => {
  const style = {
    version: 8,
    layers: [{
      id: 'place-label',
      type: 'symbol',
      'source-layer': 'place',
      layout: { 'text-size': 12 },
      paint: { 'text-color': '#333' },
    }],
  }
  const scaled = applyTweaks(style, { textScale: 1.5, buildingMinZoom: 13 })
  const out = applyColors(scaled, { ...DEFAULT_COLORS, places: '#1a1a1a' })
  assert.equal(out.layers[0].layout['text-size'], 18)
  assert.equal(out.layers[0].paint['text-color'], '#1a1a1a')
})
