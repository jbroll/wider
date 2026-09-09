import { signal, effect } from '@preact/signals'

import { places, selected } from './places.jsx'
import { toast, reapplyStyle } from './styles.jsx'
import { directionsUrl, buildBody, parseRoute, formatDistance, formatDuration } from './route.js'

const SAVE_DELAY = 300

const UNREACHABLE = 'Could not reach the routing service. Is mapper on the local network?'
const NOT_ROUTABLE = 'No walking route there; routing only covers the Schenectady area.'

export const route = signal(null)

let map = null
let timer = 0
let token = 0

async function run(ids) {
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
    const res = await fetch(directionsUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(buildBody(points)),
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

// Wired from main.jsx once the map exists. Two effects: one prunes a
// selection of a place that got deleted, the other debounces the fetch the
// same way main.jsx debounces the saved view - so ticking several places in
// a row sends one request, not one per click.
export function attachRoute(m) {
  map = m

  effect(() => {
    const ids = new Set(places.value.map((p) => p.id))
    const next = selected.value.filter((id) => ids.has(id))
    if (next.length !== selected.value.length) selected.value = next
  })

  effect(() => {
    const ids = places.value.filter((p) => selected.value.includes(p.id)).map((p) => p.id)
    clearTimeout(timer)
    timer = setTimeout(() => run(ids), SAVE_DELAY)
  })
}

export function RouteStatus() {
  const r = route.value
  if (!r) return null
  return (
    <div id="route-info">
      <span id="route-summary">{formatDistance(r.distance)} · {formatDuration(r.duration)}</span>
      <button id="route-clear" onClick={() => { selected.value = [] }}>Clear route</button>
    </div>
  )
}
