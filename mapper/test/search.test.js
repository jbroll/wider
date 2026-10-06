import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  GEOCODE_BASE_URL, MIN_CHARS, RESULT_COUNT, autocompleteUrl, parseResults, zoomFor,
} from '../src/search.js'

const TOKEN = '0123456789abcdef0123456789abcdef'
const CENTER = [-73.94, 42.81]

const query = (url) => Object.fromEntries(new URLSearchParams(url.split('?')[1]))

function feature(props, coordinates = [-73.9473, 42.8151]) {
  return { type: 'Feature', geometry: { type: 'Point', coordinates }, properties: props }
}

test('the base URL is relative to the page', () => {
  assert.equal(GEOCODE_BASE_URL, 'geocode')
})

test('autocompleteUrl asks for the text, the result count and the map center as focus', () => {
  const url = autocompleteUrl('120 state st', '', CENTER)
  assert.match(url, /^geocode\/v1\/autocomplete\?/)
  assert.deepEqual(query(url), {
    text: '120 state st',
    size: String(RESULT_COUNT),
    'focus.point.lat': '42.81',
    'focus.point.lon': '-73.94',
  })
})

test('autocompleteUrl forwards the page token and no other page parameter', () => {
  const url = autocompleteUrl('state', '?a=1&token=' + TOKEN + '&b=2', CENTER)
  assert.equal(query(url).token, TOKEN)
  assert.equal(query(url).a, undefined)
  assert.equal(query(autocompleteUrl('state', '?token=', CENTER)).token, undefined)
})

test('autocompleteUrl encodes the text', () => {
  assert.equal(query(autocompleteUrl('1 & 2 #3', '', CENTER)).text, '1 & 2 #3')
})

test('autocompleteUrl resolves under the page path, local or mounted', () => {
  const url = autocompleteUrl('state', '?token=' + TOKEN, CENTER)
  assert.match(new URL(url, 'https://apps.rkroll.com/mapper/?token=' + TOKEN).href,
    /^https:\/\/apps\.rkroll\.com\/mapper\/geocode\/v1\/autocomplete\?/)
})

test('the minimum query length matches the geocoder', () => {
  assert.equal(MIN_CHARS, 3)
})

test('parseResults takes label, layer and [lon, lat] from each feature', () => {
  const json = {
    type: 'FeatureCollection',
    features: [feature({ label: '120 State ST, Schenectady, NY', layer: 'address' })],
  }
  assert.deepEqual(parseResults(json), [
    { label: '120 State ST, Schenectady, NY', layer: 'address', lon: -73.9473, lat: 42.8151 },
  ])
})

test('parseResults falls back to name when a feature has no label', () => {
  const json = { features: [feature({ label: '', name: 'State ST', layer: 'street' })] }
  assert.equal(parseResults(json)[0].label, 'State ST')
})

test('parseResults drops features with no usable coordinates or text', () => {
  const json = {
    features: [
      feature({ label: 'No point' }, null),
      feature({ label: 'Bad point' }, ['x', 1]),
      feature({ label: '', name: '' }),
      { type: 'Feature', properties: { label: 'No geometry' } },
      feature({ label: 'Kept', layer: 'locality' }),
    ],
  }
  assert.deepEqual(parseResults(json).map((r) => r.label), ['Kept'])
})

test('parseResults returns an empty list for a malformed response', () => {
  assert.deepEqual(parseResults(null), [])
  assert.deepEqual(parseResults({}), [])
  assert.deepEqual(parseResults({ features: 'no' }), [])
})

test('zoomFor flies closer for an address than a street, and closer for a street than a town', () => {
  assert.equal(zoomFor('address'), 17)
  assert.equal(zoomFor('street'), 15)
  assert.equal(zoomFor('locality'), 12)
  assert.equal(zoomFor('postalcode'), 12)
  assert.equal(zoomFor(undefined), 12)
})
