import { createMap } from './map.js'
import { loadView, saveView } from './view.js'
import { loadStyle, styleUrl } from './styles.js'
import { loadTweaks, applyTweaks } from './tweaks.js'
import { loadColors, applyColors } from './colors.js'
import { applyRoute } from './route.js'
import { route, attachRoute, RouteStatus } from './route.jsx'
import { addStyleControl } from './styles.jsx'
import { render } from 'preact'
import { Places, attach } from './places.jsx'
import { store } from './store.js'

const NO_WEBGL = 'This window cannot draw the map: WebGL is unavailable.'
const LOAD_FAILED = 'This window cannot draw the map: the map style failed to load.'

const SAVE_DELAY = 300

// MapLibre's transformStyle hook exists only on setStyle, not on the map
// constructor, so a style loaded by URL at startup cannot be transformed on the
// way in. Fetching it here is the only way to hand the constructor an object.
// A timeout so a hung request lands on the LOAD_FAILED message below instead
// of leaving the window empty forever.
async function fetchStyle(id) {
  const res = await fetch(styleUrl(id), { signal: AbortSignal.timeout(15000) })
  if (!res.ok) throw new Error('HTTP ' + res.status)
  return res.json()
}

async function start() {
  const container = document.getElementById('map')

  let style
  try {
    style = await fetchStyle(loadStyle(store))
  } catch (err) {
    container.textContent = LOAD_FAILED
    console.error(err)
    return
  }

  let map
  try {
    map = createMap(container, loadView(store),
      applyRoute(applyColors(applyTweaks(style, loadTweaks(store)), loadColors(store)), route.value))
  } catch (err) {
    container.textContent = NO_WEBGL
    console.error(err)
    return
  }

  map.on('error', (e) => {
    // A tile error carries `tile`/`sourceId` (maplibre-gl tile/tile_manager.ts:197);
    // a style-load failure fires a bare ErrorEvent (maplibre-gl style/style.ts:449).
    // isStyleLoaded() can't tell these apart: it's false during any in-flight tile.
    if (e.tile || e.sourceId) {
      console.error(e.error)
      return
    }
    container.textContent = LOAD_FAILED
    console.error(e.error)
  })

  let timer = 0
  map.on('moveend', () => {
    clearTimeout(timer)
    timer = setTimeout(() => saveView(store, {
      center: map.getCenter().toArray(),
      zoom: map.getZoom(),
      bearing: map.getBearing(),
      pitch: map.getPitch(),
    }), SAVE_DELAY)
  })

  attach(map)
  addStyleControl(map, store, style)
  attachRoute(map)
  render(<><Places map={map} /><RouteStatus /></>, document.getElementById('panel'))

  window.mapper = { map }
}

start()
