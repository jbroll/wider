import { signal, effect } from '@preact/signals'
import maplibregl from 'maplibre-gl'

import { loadPlaces, savePlaces, addPlace, removePlace, movePlace, reorderPlace, newId } from './places.js'
import { store } from './store.js'

export const places = signal(loadPlaces(store))
const open = signal(true)
const pending = signal(null)
const dragging = signal(false)

// Membership only - waypoint order comes from list order, not from this.
export const selected = signal([])

export function toggleSelected(id) {
  const cur = selected.value
  selected.value = cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id]
}

function commit(next) {
  places.value = savePlaces(store, next)
}

function discard() {
  if (pending.value) pending.value.marker.remove()
  pending.value = null
}

function goTo(map, p) {
  map.flyTo({ center: [p.lon, p.lat], zoom: p.zoom, bearing: p.bearing })
}

// No custom element: MapLibre's own default marker is the pin, so it's the
// same icon as the pending pin and MapLibre owns the anchor math. The label
// is appended to the marker's own element, absolutely positioned so it
// carries no layout weight and can't shift where MapLibre anchors the pin.
function placeMarker(map, p) {
  const marker = new maplibregl.Marker({ draggable: true })
    .setLngLat([p.lon, p.lat])
    .addTo(map)

  const el = marker.getElement()
  el.classList.add('place-marker')

  const label = document.createElement('div')
  label.className = 'place-label'
  label.textContent = p.name
  el.append(label)

  const entry = { place: p, label, marker }

  // MapLibre sets the element's pointer-events to none for the duration of a
  // drag, so this never fires for a drag - verified in test/map.spec.js
  // rather than assumed.
  marker.on('click', () => goTo(map, entry.place))

  marker.on('dragend', () => {
    const { lat, lng } = marker.getLngLat()
    commit(movePlace(places.value, entry.place.id, lat, lng))
  })

  return entry
}

export function attach(map) {
  map.on('contextmenu', (e) => {
    discard()
    const marker = new maplibregl.Marker().setLngLat(e.lngLat).addTo(map)
    pending.value = {
      id: newId(),
      lat: e.lngLat.lat,
      lon: e.lngLat.lng,
      zoom: map.getZoom(),
      bearing: map.getBearing(),
      marker,
    }
    open.value = true
  })

  // Keyed by place id so a re-run over an unchanged list touches no marker.
  // savePlaces rebuilds every place object on each commit, so an unchanged
  // entry is detected by comparing lat/lon/name values, not identity.
  const markers = new Map()
  effect(() => {
    const ids = new Set(places.value.map((p) => p.id))
    for (const [id, entry] of markers) {
      if (!ids.has(id)) {
        entry.marker.remove()
        markers.delete(id)
      }
    }
    for (const p of places.value) {
      const entry = markers.get(p.id)
      if (!entry) {
        markers.set(p.id, placeMarker(map, p))
        continue
      }
      if (entry.place.lat !== p.lat || entry.place.lon !== p.lon || entry.place.name !== p.name) {
        entry.marker.setLngLat([p.lon, p.lat])
        entry.label.textContent = p.name
        entry.place = p
      }
    }
  })
}

export function Places({ map }) {
  const save = (name) => {
    const p = pending.value
    if (!p) return
    p.marker.remove()
    pending.value = null
    commit(addPlace(places.value, {
      id: p.id, name: name || 'Unnamed', lat: p.lat, lon: p.lon, zoom: p.zoom, bearing: p.bearing,
    }))
  }

  const go = (p) => goTo(map, p)

  // The order badge and the route both read this same list-order filter, so
  // dragging a row changes both together.
  const orderedSelected = places.value.filter((p) => selected.value.includes(p.id)).map((p) => p.id)

  const onDragStart = (id) => (e) => {
    e.dataTransfer.effectAllowed = 'move'
    e.dataTransfer.setData('text/plain', id)
    dragging.value = true
  }
  const onDragEnd = () => { dragging.value = false }
  const onDragOver = (e) => {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
  }
  const onDrop = (beforeId) => (e) => {
    e.preventDefault()
    // Stops the drop from also reaching the list's own onDrop below, which
    // would append the place instead of inserting it before this row.
    e.stopPropagation()
    const id = e.dataTransfer.getData('text/plain')
    if (id && id !== beforeId) commit(reorderPlace(places.value, id, beforeId))
  }
  // Catches a drop anywhere in the list that isn't on a row - the dropzone
  // element included, since it has no drop handler of its own and lets the
  // event bubble here. beforeId matches nothing, so reorderPlace appends.
  const onListDrop = (e) => {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain')
    if (id) commit(reorderPlace(places.value, id, undefined))
  }

  return (
    <div id="places">
      <button id="places-toggle" onClick={() => { open.value = !open.value }}>
        {open.value ? '▾' : '▸'} Places ({places.value.length})
      </button>
      {open.value && (
        <div id="places-body">
          {pending.value && (
            <input
              id="pin-name"
              autoFocus
              placeholder="Name this place"
              onKeyDown={(e) => {
                if (e.key === 'Enter') save(e.currentTarget.value.trim())
                if (e.key === 'Escape') discard()
              }}
            />
          )}
          <ul
            id="places-list"
            class={dragging.value ? 'dragging' : undefined}
            onDragOver={onDragOver}
            onDrop={onListDrop}
          >
            {places.value.map((p) => {
              const order = orderedSelected.indexOf(p.id)
              return (
                <li
                  class="place"
                  key={p.id}
                  draggable
                  onDragStart={onDragStart(p.id)}
                  onDragEnd={onDragEnd}
                  onDragOver={onDragOver}
                  onDrop={onDrop(p.id)}
                >
                  <span class="place-drag" title="Drag to reorder">⠿</span>
                  <input
                    type="checkbox"
                    class="place-check"
                    title="Include in route"
                    checked={order >= 0}
                    onChange={() => toggleSelected(p.id)}
                  />
                  <span class="place-order">{order >= 0 ? order + 1 : ''}</span>
                  <button class="place-name" onClick={() => go(p)}>{p.name}</button>
                  <button class="place-del" title="Delete" onClick={() => commit(removePlace(places.value, p.id))}>×</button>
                </li>
              )
            })}
            <li class="place-dropzone" aria-hidden="true" />
          </ul>
        </div>
      )}
    </div>
  )
}
