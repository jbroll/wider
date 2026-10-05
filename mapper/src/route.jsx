import { signal, effect } from '@preact/signals'

import { places, clearRouteChecks } from './places.jsx'
import { toast, reapplyStyle } from './styles.jsx'
import { store } from './store.js'
import {
  ROUTE_PREFS, directionsUrl, buildBody, parseRoute, formatDistance, formatDuration,
  loadRoutePref, saveRoutePref,
} from './route.js'

const SAVE_DELAY = 300

const UNREACHABLE = 'Could not reach the routing service.'
const NOT_ROUTABLE = 'No walking route there; routing only covers the Schenectady area.'

export const route = signal(null)
export const routePref = signal(loadRoutePref(store))

let map = null
let timer = 0
let token = 0

async function run(points, pref) {
  const t = ++token
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

// Wired from main.jsx once the map exists. Debounces the fetch the same way
// main.jsx debounces the saved view, so ticking several places in a row sends
// one request, not one per click.
export function attachRoute(m) {
  map = m
  effect(() => {
    const points = places.value.filter((p) => p.route)
    const pref = routePref.value
    clearTimeout(timer)
    timer = setTimeout(() => run(points, pref), SAVE_DELAY)
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
      <button id="route-clear" onClick={clearRouteChecks}>Clear route</button>
    </div>
  )
}
