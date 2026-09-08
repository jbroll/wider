import { signal, effect } from '@preact/signals'
import maplibregl from 'maplibre-gl'

import { loadPlaces, savePlaces, addPlace, removePlace, newId } from './places.js'
import { store } from './store.js'

const places = signal(loadPlaces(store))
const open = signal(true)
const pending = signal(null)

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

function placeMarker(map, p) {
  const el = document.createElement('div')
  el.className = 'place-marker'
  el.textContent = p.name
  el.addEventListener('click', (e) => {
    e.stopPropagation()
    goTo(map, p)
  })
  return new maplibregl.Marker({ element: el }).setLngLat([p.lon, p.lat]).addTo(map)
}

// Keyed by place id so a re-run over an unchanged list touches no marker,
// which is what keeps this from double-adding on re-entry.
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

  const markers = new Map()
  effect(() => {
    const ids = new Set(places.value.map((p) => p.id))
    for (const [id, marker] of markers) {
      if (!ids.has(id)) {
        marker.remove()
        markers.delete(id)
      }
    }
    for (const p of places.value) {
      if (!markers.has(p.id)) markers.set(p.id, placeMarker(map, p))
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
          <ul id="places-list">
            {places.value.map((p) => (
              <li class="place" key={p.id}>
                <button class="place-name" onClick={() => go(p)}>{p.name}</button>
                <button class="place-del" title="Delete" onClick={() => commit(removePlace(places.value, p.id))}>×</button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
