import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  PLACES_KEY, validatePlace, parsePlaces, loadPlaces, savePlaces,
  newId, addPlace, removePlace, renamePlace,
} from '../src/places.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    raw: map,
  }
}

const HOME = { id: 'a1', name: 'Home', lat: 39.1, lon: -84.5, zoom: 15, bearing: 0 }
const WORK = { id: 'b2', name: 'Work', lat: 39.2, lon: -84.4, zoom: 16, bearing: 90 }

test('a place is added to the end of the list', () => {
  const list = addPlace(addPlace([], HOME), WORK)
  assert.deepEqual(list.map((p) => p.id), ['a1', 'b2'])
})

test('add does not mutate the list it was given', () => {
  const before = [HOME]
  addPlace(before, WORK)
  assert.equal(before.length, 1)
})

test('an invalid place is not added', () => {
  assert.deepEqual(addPlace([], { id: 'x', name: 'Nowhere', lat: 99, lon: 0, zoom: 5, bearing: 0 }), [])
  assert.deepEqual(addPlace([], { name: 'No id', lat: 0, lon: 0, zoom: 5, bearing: 0 }), [])
})

test('a place is removed by id', () => {
  assert.deepEqual(removePlace([HOME, WORK], 'a1'), [WORK])
  assert.deepEqual(removePlace([HOME], 'nope'), [HOME])
})

test('a place is renamed by id', () => {
  const list = renamePlace([HOME, WORK], 'b2', 'Office')
  assert.equal(list[1].name, 'Office')
  assert.equal(list[0].name, 'Home')
  assert.equal(WORK.name, 'Work')
})

test('the list round-trips through the store', () => {
  const store = fakeStore()
  savePlaces(store, [HOME, WORK])
  assert.deepEqual(loadPlaces(store), [HOME, WORK])
  assert.ok(store.raw.has(PLACES_KEY))
})

test('ids survive a save and load', () => {
  const store = fakeStore()
  const id = newId()
  savePlaces(store, [{ ...HOME, id }])
  assert.equal(loadPlaces(store)[0].id, id)
})

test('two new ids differ', () => {
  assert.notEqual(newId(), newId())
})

test('a missing key gives an empty list', () => {
  assert.deepEqual(loadPlaces(fakeStore()), [])
})

test('malformed storage gives an empty list', () => {
  assert.deepEqual(parsePlaces('{not json'), [])
  assert.deepEqual(parsePlaces('{"id":"a1"}'), [])
  assert.deepEqual(parsePlaces(null), [])
})

test('an invalid entry is dropped and the valid ones survive', () => {
  const raw = JSON.stringify([HOME, { id: 'bad', name: 'Bad', lat: 'x', lon: 0, zoom: 5, bearing: 0 }, WORK])
  assert.deepEqual(parsePlaces(raw).map((p) => p.id), ['a1', 'b2'])
})

test('bearing is normalized into a single turn', () => {
  assert.equal(validatePlace({ ...HOME, bearing: -90 }).bearing, 270)
})
