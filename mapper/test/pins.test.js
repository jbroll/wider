import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  PINS_KEY, DEFAULT_PINS, ICON_MIN_SCALE, validatePins, parsePins, loadPins, savePins, pinCss,
} from '../src/pins.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    raw: map,
  }
}

test('the defaults are 100%, the default text color and the default background', () => {
  assert.equal(PINS_KEY, 'mapper.pins')
  assert.deepEqual(DEFAULT_PINS, { scale: 1, iconScale: 1, text: null, background: null })
})

test('a saved pins value round-trips', () => {
  const pins = { scale: 2.5, iconScale: 3.1, text: '#ffcc00', background: 'transparent' }
  const store = fakeStore()
  assert.deepEqual(savePins(store, pins), pins)
  assert.deepEqual(loadPins(store), pins)
  assert.ok(store.raw.has(PINS_KEY))
})

test('a missing key or a malformed document gives the defaults', () => {
  assert.deepEqual(loadPins(fakeStore()), DEFAULT_PINS)
  assert.deepEqual(parsePins('{not json'), DEFAULT_PINS)
  assert.deepEqual(parsePins('[]'), DEFAULT_PINS)
  assert.deepEqual(parsePins('null'), DEFAULT_PINS)
})

test('a bad field falls back alone and leaves the others standing', () => {
  assert.deepEqual(validatePins({ scale: 1.25, iconScale: 2, text: '#ffcc00', background: '#123456' }),
    { scale: 1, iconScale: 2, text: '#ffcc00', background: '#123456' })
  assert.deepEqual(validatePins({ scale: 1.5, iconScale: 0.4, text: '#ffcc00', background: '#123456' }),
    { scale: 1.5, iconScale: 1, text: '#ffcc00', background: '#123456' })
  assert.deepEqual(validatePins({ scale: 1.5, iconScale: 2, text: 'red', background: '#123456' }),
    { scale: 1.5, iconScale: 2, text: null, background: '#123456' })
  assert.deepEqual(validatePins({ scale: 1.5, iconScale: 2, text: '#ffcc00', background: 'none' }),
    { scale: 1.5, iconScale: 2, text: '#ffcc00', background: null })
})

test('the icon scale goes down to 50% and the label scale stops at 100%', () => {
  assert.equal(ICON_MIN_SCALE, 0.5)
  assert.equal(validatePins({ scale: 1, iconScale: 0.5 }).iconScale, 0.5)
  assert.equal(validatePins({ scale: 1, iconScale: 0.4 }).iconScale, 1)
  assert.equal(validatePins({ scale: 0.5, iconScale: 1 }).scale, 1)
})

test('a pins value saved before iconScale existed keeps its label scale', () => {
  assert.deepEqual(parsePins(JSON.stringify({ scale: 1.5, text: null, background: null })),
    { scale: 1.5, iconScale: 1, text: null, background: null })
})

test('the default pins draw white text on the translucent dark background with no outline', () => {
  assert.deepEqual(pinCss(DEFAULT_PINS), {
    '--pin-scale': '1',
    '--icon-scale': '1',
    '--pin-text': '#ffffff',
    '--pin-background': 'rgba(28, 28, 28, 0.82)',
    '--pin-halo': 'none',
  })
})

test('chosen colors and scale pass straight through', () => {
  const css = pinCss({ scale: 2.4, iconScale: 1.7, text: '#ffcc00', background: '#123456' })
  assert.equal(css['--pin-scale'], '2.4')
  assert.equal(css['--icon-scale'], '1.7')
  assert.equal(css['--pin-text'], '#ffcc00')
  assert.equal(css['--pin-background'], '#123456')
  assert.equal(css['--pin-halo'], 'none')
})

test('a transparent background outlines the text in the contrasting color', () => {
  const light = pinCss({ scale: 1, text: null, background: 'transparent' })
  assert.equal(light['--pin-background'], 'transparent')
  assert.match(light['--pin-halo'], /#000000/)
  assert.doesNotMatch(light['--pin-halo'], /#ffffff/)
  const dark = pinCss({ scale: 1, text: '#111111', background: 'transparent' })
  assert.match(dark['--pin-halo'], /#ffffff/)
})
