import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  ORS_BASE_URL, PROFILE, ROUTE_SOURCE_ID, ROUTE_LAYER_ID,
  directionsUrl, buildBody, parseRoute, applyRoute, formatDistance, formatDuration,
} from '../src/route.js'

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

test('the base URL and profile are as investigated', () => {
  assert.equal(ORS_BASE_URL, 'http://192.168.1.169:8082/ors')
  assert.equal(PROFILE, 'foot-walking')
  assert.equal(directionsUrl(), 'http://192.168.1.169:8082/ors/v2/directions/foot-walking/geojson')
})

test('buildBody orders coordinates as [lon, lat] in selection order', () => {
  const points = [
    { lat: 42.8142, lon: -73.9396 },
    { lat: 42.8090, lon: -73.9310 },
    { lat: 42.8200, lon: -73.9200 },
  ]
  assert.deepEqual(buildBody(points), {
    coordinates: [[-73.9396, 42.8142], [-73.9310, 42.8090], [-73.9200, 42.82]],
  })
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
