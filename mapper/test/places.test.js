import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  PLACES_KEY, validatePlace, validatePlaces, parsePlaces, loadPlaces, savePlaces,
  newId, addPlace, removePlace, renamePlace, movePlace, reorderPlace,
  ICONS, DEFAULT_ICON, iconFor, setPlaceIcon, setPlaceHidden,
  togglePlaceRoute, clearRoute, markRoute, migrateRouteSelected,
} from '../src/places.js'

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed))
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    removeItem: (k) => map.delete(k),
    raw: map,
  }
}

const HOME = { id: 'a1', name: 'Home', lat: 39.1, lon: -84.5, zoom: 15, bearing: 0, icon: 'pin', hidden: false, route: false }
const WORK = { id: 'b2', name: 'Work', lat: 39.2, lon: -84.4, zoom: 16, bearing: 90, icon: 'star', hidden: false, route: false }

test('a place is shown unless hidden is exactly true', () => {
  const { hidden, ...old } = HOME
  assert.equal(validatePlace(old).hidden, false)
  assert.equal(validatePlace({ ...HOME, hidden: 'yes' }).hidden, false)
  assert.equal(validatePlace({ ...HOME, hidden: true }).hidden, true)
})

test('a hidden place round-trips through the store', () => {
  const store = fakeStore()
  savePlaces(store, [{ ...HOME, hidden: true }])
  assert.equal(loadPlaces(store)[0].hidden, true)
})

test('setPlaceHidden changes only the named place', () => {
  const list = setPlaceHidden([HOME, WORK], 'b2', true)
  assert.equal(list[0], HOME)
  assert.equal(list[1].hidden, true)
  assert.equal(setPlaceHidden(list, 'b2', false)[1].hidden, false)
})

test('a place is in the route only when route is exactly true', () => {
  const { route, ...old } = HOME
  assert.equal(validatePlace(old).route, false)
  assert.equal(validatePlace({ ...HOME, route: 'yes' }).route, false)
  assert.equal(validatePlace({ ...HOME, route: 1 }).route, false)
  assert.equal(validatePlace({ ...HOME, route: true }).route, true)
})

test('the route flag round-trips through the store', () => {
  const store = fakeStore()
  savePlaces(store, [{ ...HOME, route: true }, WORK])
  assert.deepEqual(loadPlaces(store).map((p) => p.route), [true, false])
})

test('togglePlaceRoute flips only the named place and leaves hidden alone', () => {
  const list = togglePlaceRoute([{ ...HOME, hidden: true }, WORK], 'a1')
  assert.equal(list[0].route, true)
  assert.equal(list[0].hidden, true)
  assert.equal(list[1], WORK)
  assert.equal(togglePlaceRoute(list, 'a1')[0].route, false)
  assert.equal(HOME.route, false)
})

test('hiding a place keeps its route flag', () => {
  const list = setPlaceHidden([{ ...HOME, route: true }], 'a1', true)
  assert.equal(list[0].route, true)
})

test('clearRoute unchecks every place and changes nothing else', () => {
  const list = clearRoute([{ ...HOME, route: true }, WORK])
  assert.deepEqual(list, [HOME, WORK])
  assert.equal(list[1], WORK)
})

test('markRoute checks the named places and ignores unknown ids', () => {
  const list = markRoute([HOME, WORK], ['b2', 'zz', 7])
  assert.deepEqual(list.map((p) => p.route), [false, true])
})

test('a stored mapper.routeSelected is folded into the places and removed', () => {
  const store = fakeStore({ 'mapper.routeSelected': '["b2","gone"]' })
  savePlaces(store, [HOME, WORK])
  migrateRouteSelected(store)
  assert.deepEqual(loadPlaces(store).map((p) => p.route), [false, true])
  assert.equal(store.raw.has('mapper.routeSelected'), false)
})

test('an unreadable mapper.routeSelected is removed and checks nothing', () => {
  const store = fakeStore({ 'mapper.routeSelected': '{not json' })
  savePlaces(store, [HOME])
  const before = store.raw.get(PLACES_KEY)
  migrateRouteSelected(store)
  assert.equal(store.raw.get(PLACES_KEY), before)
  assert.equal(store.raw.has('mapper.routeSelected'), false)
})

test('the migration writes no places key when there are no places', () => {
  const store = fakeStore({ 'mapper.routeSelected': '["a1"]' })
  migrateRouteSelected(store)
  assert.equal(store.raw.has(PLACES_KEY), false)
  assert.equal(store.raw.has('mapper.routeSelected'), false)
})

test('with no mapper.routeSelected the migration touches nothing', () => {
  const store = fakeStore()
  savePlaces(store, [{ ...HOME, route: true }])
  const before = store.raw.get(PLACES_KEY)
  migrateRouteSelected(store)
  assert.equal(store.raw.get(PLACES_KEY), before)
})

test('the icons are pin, star and finish flag, with pin the default', () => {
  assert.deepEqual(ICONS.map((i) => i.id), ['pin', 'star', 'finish'])
  assert.equal(DEFAULT_ICON, 'pin')
  assert.equal(iconFor('star').emoji, '⭐')
  assert.equal(iconFor('finish').emoji, '🏁')
  assert.equal(iconFor('nope').id, 'pin')
})

test('a place saved before icons existed loads as a pin', () => {
  const { icon, ...old } = HOME
  assert.equal(validatePlace(old).icon, 'pin')
})

test('an unknown icon falls back to pin without dropping the place', () => {
  assert.equal(validatePlace({ ...HOME, icon: 'unicorn' }).icon, 'pin')
  assert.equal(validatePlace({ ...HOME, icon: 7 }).icon, 'pin')
})

test('a place icon round-trips through the store', () => {
  const store = fakeStore()
  savePlaces(store, [{ ...HOME, icon: 'finish' }])
  assert.equal(loadPlaces(store)[0].icon, 'finish')
})

test('setPlaceIcon changes only the named place and ignores an unknown icon', () => {
  const list = setPlaceIcon([HOME, WORK], 'a1', 'finish')
  assert.equal(list[0].icon, 'finish')
  assert.equal(list[1], WORK)
  assert.deepEqual(setPlaceIcon([HOME], 'a1', 'unicorn'), [HOME])
  const before = [HOME]
  setPlaceIcon(before, 'a1', 'star')
  assert.equal(before[0].icon, 'pin')
})

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

test('validatePlaces rejects anything but an array and cleans the entries of one', () => {
  assert.equal(validatePlaces({ id: 'a1' }), null)
  assert.equal(validatePlaces(null), null)
  assert.deepEqual(validatePlaces([HOME, { id: '' }]), [HOME])
})

test('bearing is normalized into a single turn', () => {
  assert.equal(validatePlace({ ...HOME, bearing: -90 }).bearing, 270)
})

test('a place is moved to a new lat/lon by id', () => {
  const list = movePlace([HOME, WORK], 'a1', 39.5, -84.9)
  assert.equal(list[0].lat, 39.5)
  assert.equal(list[0].lon, -84.9)
  assert.equal(list[1], WORK)
})

test('moving an unknown id leaves the list unchanged', () => {
  assert.deepEqual(movePlace([HOME], 'nope', 1, 1), [HOME])
})

test('moving to an invalid position leaves the place unchanged', () => {
  const list = movePlace([HOME], 'a1', 99, 0)
  assert.deepEqual(list, [HOME])
})

test('move does not mutate the list it was given', () => {
  const before = [HOME]
  movePlace(before, 'a1', 1, 1)
  assert.equal(before[0].lat, HOME.lat)
})

test('a place is reordered to just before another place', () => {
  const CHARLIE = { ...HOME, id: 'c3', name: 'Charlie' }
  const list = reorderPlace([HOME, WORK, CHARLIE], 'c3', 'a1')
  assert.deepEqual(list.map((p) => p.id), ['c3', 'a1', 'b2'])
})

test('reordering to the end when there is no target appends it there', () => {
  const list = reorderPlace([HOME, WORK], 'a1', undefined)
  assert.deepEqual(list.map((p) => p.id), ['b2', 'a1'])
})

test('reordering a place before itself, or an unknown id, leaves the list unchanged', () => {
  assert.deepEqual(reorderPlace([HOME, WORK], 'a1', 'a1').map((p) => p.id), ['a1', 'b2'])
  assert.deepEqual(reorderPlace([HOME, WORK], 'nope', 'a1').map((p) => p.id), ['a1', 'b2'])
})

test('reorder does not mutate the list it was given', () => {
  const before = [HOME, WORK]
  reorderPlace(before, 'b2', 'a1')
  assert.deepEqual(before.map((p) => p.id), ['a1', 'b2'])
})
