import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  STYLE_KEY, DEFAULT_STYLE_ID, STYLES, validateStyleId, styleUrl, loadStyle, saveStyle,
} from '../src/styles.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    raw: map,
  }
}

test('the five styles are listed and each resolves to a URL', () => {
  assert.deepEqual(STYLES.map((s) => s.id), ['liberty', 'bright', 'positron', 'dark', 'fiord'])
  for (const s of STYLES) {
    assert.equal(styleUrl(s.id), s.url)
    assert.equal(s.url, 'https://tiles.openfreemap.org/styles/' + s.id)
    assert.ok(s.name.length > 0)
  }
})

test('liberty is the default and is itself a listed style', () => {
  assert.equal(DEFAULT_STYLE_ID, 'liberty')
  assert.equal(validateStyleId(DEFAULT_STYLE_ID), DEFAULT_STYLE_ID)
})

test('a saved style round-trips', () => {
  const store = fakeStore()
  assert.equal(saveStyle(store, 'dark'), 'dark')
  assert.equal(loadStyle(store), 'dark')
  assert.equal(store.raw.size, 1)
  assert.ok(store.raw.has(STYLE_KEY))
})

test('a missing key gives the default style', () => {
  assert.equal(loadStyle(fakeStore()), DEFAULT_STYLE_ID)
})

test('an unknown id gives the default style', () => {
  assert.equal(loadStyle(fakeStore({ [STYLE_KEY]: '3d' })), DEFAULT_STYLE_ID)
  assert.equal(validateStyleId('3d'), null)
  assert.equal(styleUrl('3d'), styleUrl(DEFAULT_STYLE_ID))
})

test('a malformed value gives the default style', () => {
  assert.equal(loadStyle(fakeStore({ [STYLE_KEY]: '' })), DEFAULT_STYLE_ID)
  assert.equal(loadStyle(fakeStore({ [STYLE_KEY]: '{"id":"dark"}' })), DEFAULT_STYLE_ID)
  assert.equal(validateStyleId(null), null)
  assert.equal(validateStyleId(7), null)
  assert.equal(validateStyleId({ id: 'dark' }), null)
  assert.equal(styleUrl(undefined), styleUrl(DEFAULT_STYLE_ID))
})

test('saving an invalid id writes nothing', () => {
  const store = fakeStore()
  assert.equal(saveStyle(store, 'nope'), null)
  assert.equal(store.raw.size, 0)
})
