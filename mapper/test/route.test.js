import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  ORS_BASE_URL, PROFILE, ROUTE_SOURCE_ID, ROUTE_LAYER_ID, ROUTE_PREF_KEY, ROUTE_PREFS, ROUTE_SELECTED_KEY,
  directionsUrl, buildBody, parseRoute, applyRoute, formatDistance, formatDuration,
  loadRoutePref, saveRoutePref, validateRouteSelected, loadRouteSelected, saveRouteSelected, pruneSelected,
} from '../src/route.js'

function memoryStore(initial = {}) {
  const data = { ...initial }
  return {
    data,
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v) },
  }
}

function stub() {
  return {
    version: 8,
    name: 'stub',
    sources: { empty: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } } },
    layers: [
      { id: 'bg', type: 'background', paint: { 'background-color': '#fff' } },
    ],
  }
}

const GEOMETRY = { type: 'LineString', coordinates: [[-73.94, 42.81], [-73.93, 42.81]] }

const ORS_RESPONSE = {
  type: 'FeatureCollection',
  features: [{
    type: 'Feature',
    geometry: GEOMETRY,
    properties: { segments: [{ distance: 1234.5, duration: 987.6 }] },
  }],
}

const DIRECTIONS = 'ors/v2/directions/foot-walking/geojson'
const TOKEN = '0123456789abcdef0123456789abcdef'

test('the base URL is relative to the page and the profile is walking', () => {
  assert.equal(ORS_BASE_URL, 'ors')
  assert.equal(PROFILE, 'foot-walking')
})

test('directionsUrl carries no query when the page has none', () => {
  assert.equal(directionsUrl(), DIRECTIONS)
  assert.equal(directionsUrl(''), DIRECTIONS)
})

test('directionsUrl forwards the page token', () => {
  assert.equal(directionsUrl('?token=' + TOKEN), DIRECTIONS + '?token=' + TOKEN)
})

test('directionsUrl forwards only the token, not other page parameters', () => {
  assert.equal(directionsUrl('?a=1&token=' + TOKEN + '&b=2'), DIRECTIONS + '?token=' + TOKEN)
  assert.equal(directionsUrl('?a=1&b=2'), DIRECTIONS)
})

test('directionsUrl drops an empty token', () => {
  assert.equal(directionsUrl('?token='), DIRECTIONS)
})

test('directionsUrl encodes the token', () => {
  assert.equal(directionsUrl('?token=a%26b'), DIRECTIONS + '?token=a%26b')
})

test('directionsUrl resolves under the page path, local or mounted', () => {
  assert.equal(new URL(directionsUrl(), 'http://127.0.0.1:8737/').href,
    'http://127.0.0.1:8737/' + DIRECTIONS)
  assert.equal(new URL(directionsUrl('?token=' + TOKEN), 'https://apps.rkroll.com/mapper/?token=' + TOKEN).href,
    'https://apps.rkroll.com/mapper/' + DIRECTIONS + '?token=' + TOKEN)
})

test('buildBody orders coordinates as [lon, lat] in selection order', () => {
  const points = [
    { lat: 42.8142, lon: -73.9396 },
    { lat: 42.8090, lon: -73.9310 },
    { lat: 42.8200, lon: -73.9200 },
  ]
  assert.deepEqual(buildBody(points).coordinates,
    [[-73.9396, 42.8142], [-73.9310, 42.8090], [-73.9200, 42.82]])
})

const TWO = [{ lat: 42.80, lon: -73.93 }, { lat: 42.81, lon: -73.94 }]

test('the route preferences are Direct (shortest) then Quiet (recommended)', () => {
  assert.deepEqual(ROUTE_PREFS.map((p) => [p.id, p.name]),
    [['shortest', 'Direct'], ['recommended', 'Quiet']])
})

test('buildBody sends the given preference', () => {
  assert.equal(buildBody(TWO, 'shortest').preference, 'shortest')
  assert.equal(buildBody(TWO, 'recommended').preference, 'recommended')
})

test('buildBody falls back to shortest for a missing or unknown preference', () => {
  assert.equal(buildBody(TWO).preference, 'shortest')
  assert.equal(buildBody(TWO, 'fastest').preference, 'shortest')
})

test('loadRoutePref returns the saved preference', () => {
  assert.equal(loadRoutePref(memoryStore({ [ROUTE_PREF_KEY]: 'recommended' })), 'recommended')
})

test('loadRoutePref falls back to shortest for a missing or unrecognised value', () => {
  assert.equal(ROUTE_PREF_KEY, 'mapper.routePref')
  assert.equal(loadRoutePref(memoryStore()), 'shortest')
  assert.equal(loadRoutePref(memoryStore({ [ROUTE_PREF_KEY]: 'scenic' })), 'shortest')
})

test('saveRoutePref stores a valid preference and ignores an invalid one', () => {
  const s = memoryStore()
  assert.equal(saveRoutePref(s, 'recommended'), 'recommended')
  assert.equal(s.data[ROUTE_PREF_KEY], 'recommended')
  assert.equal(saveRoutePref(s, 'scenic'), null)
  assert.equal(s.data[ROUTE_PREF_KEY], 'recommended')
})

test('the route selection is stored under mapper.routeSelected', () => {
  assert.equal(ROUTE_SELECTED_KEY, 'mapper.routeSelected')
})

test('validateRouteSelected keeps an array of id strings as it is', () => {
  assert.deepEqual(validateRouteSelected(['a', 'b']), ['a', 'b'])
  assert.deepEqual(validateRouteSelected([]), [])
})

test('validateRouteSelected drops invalid entries one by one', () => {
  assert.deepEqual(validateRouteSelected(['a', '', 3, null, { id: 'b' }, 'c']), ['a', 'c'])
})

test('validateRouteSelected rejects anything but an array', () => {
  for (const v of [null, undefined, 'a', 1, { a: 1 }]) assert.equal(validateRouteSelected(v), null)
})

test('loadRouteSelected returns the saved ids in saved order', () => {
  assert.deepEqual(loadRouteSelected(memoryStore({ [ROUTE_SELECTED_KEY]: '["b","a"]' })), ['b', 'a'])
})

test('loadRouteSelected falls back to an empty selection', () => {
  assert.deepEqual(loadRouteSelected(memoryStore()), [])
  assert.deepEqual(loadRouteSelected(memoryStore({ [ROUTE_SELECTED_KEY]: '{not json' })), [])
  assert.deepEqual(loadRouteSelected(memoryStore({ [ROUTE_SELECTED_KEY]: '{"a":1}' })), [])
  assert.deepEqual(loadRouteSelected(memoryStore({ [ROUTE_SELECTED_KEY]: '"a"' })), [])
})

test('loadRouteSelected drops an invalid entry and keeps the rest', () => {
  assert.deepEqual(loadRouteSelected(memoryStore({ [ROUTE_SELECTED_KEY]: '["a",7,"b"]' })), ['a', 'b'])
})

test('saveRouteSelected stores the cleaned ids as a JSON array', () => {
  const s = memoryStore()
  assert.deepEqual(saveRouteSelected(s, ['a', 5, 'b']), ['a', 'b'])
  assert.equal(s.data[ROUTE_SELECTED_KEY], '["a","b"]')
  assert.deepEqual(saveRouteSelected(s, []), [])
  assert.equal(s.data[ROUTE_SELECTED_KEY], '[]')
  assert.deepEqual(loadRouteSelected(s), [])
})

test('pruneSelected drops ids with no place and keeps the rest in their order', () => {
  const places = [{ id: 'a' }, { id: 'b' }, { id: 'c' }]
  assert.deepEqual(pruneSelected(['c', 'x', 'a'], places), ['c', 'a'])
  assert.deepEqual(pruneSelected(['x'], []), [])
})

test('parseRoute pulls geometry, distance and duration from the ORS response', () => {
  const route = parseRoute(ORS_RESPONSE)
  assert.deepEqual(route.geometry, GEOMETRY)
  assert.equal(route.distance, 1234.5)
  assert.equal(route.duration, 987.6)
})

test('parseRoute returns null for a response with no feature', () => {
  assert.equal(parseRoute({ type: 'FeatureCollection', features: [] }), null)
  assert.equal(parseRoute(null), null)
  assert.equal(parseRoute({}), null)
})

test('formatDistance switches from metres to kilometres at 1000m', () => {
  assert.equal(formatDistance(250), '250 m')
  assert.equal(formatDistance(999), '999 m')
  assert.equal(formatDistance(1000), '1.0 km')
  assert.equal(formatDistance(2340), '2.3 km')
})

test('formatDuration rounds to whole minutes, minimum one', () => {
  assert.equal(formatDuration(30), '1 min')
  assert.equal(formatDuration(90), '2 min')
  assert.equal(formatDuration(600), '10 min')
})

test('applyRoute appends exactly one source and one layer', () => {
  const out = applyRoute(stub(), { geometry: GEOMETRY })
  assert.equal(Object.keys(out.sources).length, Object.keys(stub().sources).length + 1)
  assert.equal(out.layers.length, stub().layers.length + 1)
  assert.ok(out.sources[ROUTE_SOURCE_ID])
  assert.equal(out.sources[ROUTE_SOURCE_ID].type, 'geojson')
  assert.deepEqual(out.sources[ROUTE_SOURCE_ID].data.geometry, GEOMETRY)
  const layer = out.layers.find((l) => l.id === ROUTE_LAYER_ID)
  assert.ok(layer)
  assert.equal(layer.type, 'line')
  assert.equal(layer.source, ROUTE_SOURCE_ID)
})

test('the route line is drawn as round blue dots, not a solid stroke', () => {
  const layer = applyRoute(stub(), { geometry: GEOMETRY }).layers.find((l) => l.id === ROUTE_LAYER_ID)
  assert.equal(layer.layout['line-cap'], 'round')
  assert.equal(layer.paint['line-dasharray'][0], 0)
  assert.ok(layer.paint['line-dasharray'][1] > 0)
  assert.match(layer.paint['line-color'], /^#[0-9a-f]{6}$/i)
  assert.notEqual(layer.paint['line-color'].toLowerCase(), '#ff5a00')
})

test('a null or geometry-less route leaves the style unchanged', () => {
  assert.deepEqual(applyRoute(stub(), null), stub())
  assert.deepEqual(applyRoute(stub(), undefined), stub())
  assert.deepEqual(applyRoute(stub(), {}), stub())
})

test('a style with no layers is returned as it is', () => {
  assert.equal(applyRoute(null, { geometry: GEOMETRY }), null)
  assert.deepEqual(applyRoute({ version: 8 }, { geometry: GEOMETRY }), { version: 8 })
})

test('the input style is not mutated', () => {
  const input = stub()
  const before = JSON.stringify(input)
  const out = applyRoute(input, { geometry: GEOMETRY })
  assert.equal(JSON.stringify(input), before)
  assert.notEqual(out, input)
  assert.notEqual(out.layers, input.layers)
  assert.notEqual(out.sources, input.sources)
})

test('applying twice to the same input does not compound', () => {
  const once = applyRoute(stub(), { geometry: GEOMETRY })
  const twice = applyRoute(once, { geometry: GEOMETRY })
  assert.equal(twice.layers.length, once.layers.length)
  assert.equal(Object.keys(twice.sources).length, Object.keys(once.sources).length)
})
