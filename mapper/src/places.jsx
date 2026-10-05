import { signal, effect, untracked } from '@preact/signals'
import maplibregl from 'maplibre-gl'

import {
  ICONS, iconFor, loadPlaces, savePlaces, addPlace, removePlace, movePlace, reorderPlace,
  setPlaceIcon, setPlaceHidden, togglePlaceRoute, clearRoute, migrateRouteSelected, newId,
} from './places.js'
import { store } from './store.js'
import { tweaks } from './tweaks.jsx'
import { pins } from './pins.jsx'

// MapLibre centres its default pin on the coordinate and lifts it this many
// px so the tip lands there instead. CSS scales the pin; the lift must follow.
const PIN_LIFT = 14

const markerScale = () => tweaks.value.textScale * pins.value.iconScale

migrateRouteSelected(store)
export const places = signal(loadPlaces(store))
const open = signal(true)
const pending = signal(null)
const dragging = signal(false)
// The id of the place whose icon menu is open.
const iconMenu = signal(null)

function commit(next) {
  places.value = savePlaces(store, next)
}

export function clearRouteChecks() {
  commit(clearRoute(places.value))
}

function discard() {
  if (pending.value) pending.value.marker.remove()
  pending.value = null
}

function goTo(map, p) {
  map.flyTo({ center: [p.lon, p.lat], zoom: p.zoom, bearing: p.bearing })
}

function emojiElement(icon) {
  const el = document.createElement('div')
  const glyph = document.createElement('span')
  glyph.className = 'place-emoji'
  glyph.textContent = icon.emoji
  glyph.style.marginLeft = icon.shift + 'em'
  el.append(glyph)
  return el
}

const pinOffset = (scale) => [0, -PIN_LIFT * scale]

// The pin is MapLibre's own default marker, the same icon as the pending pin;
// an emoji icon is a custom element on the anchor its table entry names.
// Either way MapLibre owns the anchor math. The label is appended to the
// marker's own element, absolutely positioned so it carries no layout weight
// and can't shift where MapLibre anchors the marker.
function placeMarker(map, p) {
  const icon = iconFor(p.icon)
  const options = icon.anchor
    ? { element: emojiElement(icon), anchor: icon.anchor, draggable: true }
    : { offset: pinOffset(untracked(markerScale)), draggable: true }
  const marker = new maplibregl.Marker(options)
    .setLngLat([p.lon, p.lat])
    .addTo(map)

  const el = marker.getElement()
  el.classList.add('place-marker')
  el.dataset.icon = icon.id

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

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') iconMenu.value = null
  })
  document.addEventListener('pointerdown', (e) => {
    if (iconMenu.value && !e.target.closest('.icon-menu, .place-icon')) iconMenu.value = null
  })

  // Keyed by place id so a re-run over an unchanged list touches no marker.
  // savePlaces rebuilds every place object on each commit, so an unchanged
  // entry is detected by comparing lat/lon/name values, not identity. A
  // marker's element is fixed at construction, so a new icon means a new marker.
  // A hidden place has no marker at all, the same as a deleted one.
  const markers = new Map()
  effect(() => {
    const shown = places.value.filter((p) => !p.hidden)
    const ids = new Set(shown.map((p) => p.id))
    for (const [id, entry] of markers) {
      if (!ids.has(id)) {
        entry.marker.remove()
        markers.delete(id)
      }
    }
    for (const p of shown) {
      const entry = markers.get(p.id)
      if (entry && entry.place.icon !== p.icon) {
        entry.marker.remove()
        markers.delete(p.id)
      }
      if (!markers.has(p.id)) {
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

  effect(() => {
    const offset = pinOffset(markerScale())
    for (const entry of markers.values()) {
      if (!iconFor(entry.place.icon).anchor) entry.marker.setOffset(offset)
    }
  })
}

function EyeIcon({ off }) {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"
      fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z" />
      <circle cx="12" cy="12" r="3" />
      {off && <line x1="3" y1="3" x2="21" y2="21" />}
    </svg>
  )
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
  const routeIds = places.value.filter((p) => p.route).map((p) => p.id)

  const pickIcon = (id, icon) => {
    iconMenu.value = null
    commit(setPlaceIcon(places.value, id, icon))
  }

  const onDragStart = (id) => (e) => {
    iconMenu.value = null
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
              const order = routeIds.indexOf(p.id)
              const menuOpen = iconMenu.value === p.id
              return [
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
                    checked={p.route}
                    onChange={() => commit(togglePlaceRoute(places.value, p.id))}
                  />
                  <span class="place-order">{order >= 0 ? order + 1 : ''}</span>
                  <button
                    class="place-icon"
                    title="Choose the map icon"
                    aria-haspopup="menu"
                    aria-expanded={menuOpen}
                    onClick={() => { iconMenu.value = menuOpen ? null : p.id }}
                  >
                    {iconFor(p.icon).emoji}
                  </button>
                  <button class="place-name" onClick={() => go(p)}>{p.name}</button>
                  <button
                    class="place-hide"
                    title={p.hidden ? 'Show on the map' : 'Hide from the map'}
                    aria-pressed={p.hidden}
                    onClick={() => commit(setPlaceHidden(places.value, p.id, !p.hidden))}
                  >
                    <EyeIcon off={p.hidden} />
                  </button>
                  <button class="place-del" title="Delete" onClick={() => commit(removePlace(places.value, p.id))}>×</button>
                </li>,
                menuOpen && (
                  <li class="icon-menu" key={p.id + '-icons'} role="menu">
                    {ICONS.map((i) => (
                      <button
                        key={i.id}
                        class={'icon-option' + (i.id === p.icon ? ' current' : '')}
                        role="menuitem"
                        data-icon={i.id}
                        onClick={() => pickIcon(p.id, i.id)}
                      >
                        {i.emoji} {i.name}
                      </button>
                    ))}
                  </li>
                ),
              ]
            })}
            <li class="place-dropzone" aria-hidden="true" />
          </ul>
        </div>
      )}
    </div>
  )
}
