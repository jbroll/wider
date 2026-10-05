import { signal, effect } from '@preact/signals'

import { places, selected } from './places.jsx'
import { toast, reapplyStyle } from './styles.jsx'
import { store } from './store.js'
import {
  ROUTE_PREFS, directionsUrl, buildBody, parseRoute, formatDistance, formatDuration,
  loadRoutePref, saveRoutePref, loadRouteSelected, saveRouteSelected, pruneSelected,
} from './route.js'

const SAVE_DELAY = 300

const UNREACHABLE = 'Could not reach the routing service.'
const NOT_ROUTABLE = 'No walking route there; routing only covers the Schenectady area.'

export const route = signal(null)
export const routePref = signal(loadRoutePref(store))

let map = null
let timer = 0
let token = 0

async function run(ids, pref) {
  const t = ++token
  const points = ids.map((id) => places.value.find((p) => p.id === id)).filter(Boolean)
  if (points.length < 2) {
    if (route.value !== null) {
      route.value = null
      reapplyStyle(map)
    }
    return
  }
  let json
  try {
    const res = await fetch(directionsUrl(window.location.search), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(buildBody(points, pref)),
    })
    if (t !== token) return
    if (res.status === 404) {
      toast(NOT_ROUTABLE)
      return
    }
    if (!res.ok) {
      toast(UNREACHABLE)
      return
    }
    json = await res.json()
  } catch (err) {
    if (t !== token) return
    console.error(err)
    toast(UNREACHABLE)
    return
  }
  if (t !== token) return
  route.value = parseRoute(json)
  reapplyStyle(map)
}

// Wired from main.jsx once the map exists. The effects prune a selection of
// a place that got deleted, save the selection, and debounce the fetch the
// same way main.jsx debounces the saved view - so ticking several places in
// a row sends one request, not one per click.
export function attachRoute(m) {
  map = m
  selected.value = pruneSelected(loadRouteSelected(store), places.value)

  effect(() => {
    const next = pruneSelected(selected.value, places.value)
    if (next.length !== selected.value.length) selected.value = next
  })

  // Skips the first run so a load alone never writes the key.
  let loading = true
  effect(() => {
    const ids = selected.value
    if (loading) loading = false
    else saveRouteSelected(store, ids)
  })

  effect(() => {
    const ids = places.value.filter((p) => selected.value.includes(p.id)).map((p) => p.id)
    const pref = routePref.value
    clearTimeout(timer)
    timer = setTimeout(() => run(ids, pref), SAVE_DELAY)
  })
}

function setRoutePref(id) {
  routePref.value = saveRoutePref(store, id) || routePref.value
}

export function RouteStatus() {
  const r = route.value
  if (!r) return null
  return (
    <div id="route-info">
      <span id="route-summary">{formatDistance(r.distance)} · {formatDuration(r.duration)}</span>
      <span class="route-prefs">
        {ROUTE_PREFS.map((p) => (
          <button
            key={p.id}
            class={'route-pref' + (routePref.value === p.id ? ' current' : '')}
            data-pref={p.id}
            aria-pressed={routePref.value === p.id}
            onClick={() => setRoutePref(p.id)}
          >
            {p.name}
          </button>
        ))}
      </span>
      <button id="route-clear" onClick={() => { selected.value = [] }}>Clear route</button>
    </div>
  )
}
