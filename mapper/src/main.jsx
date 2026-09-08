import { createMap } from './map.js'
import { loadView, saveView } from './view.js'
import { render } from 'preact'
import { Places, attach } from './places.jsx'
import { store } from './store.js'

const NO_WEBGL = 'This window cannot draw the map: WebGL is unavailable.'
const LOAD_FAILED = 'This window cannot draw the map: the map style failed to load.'

const SAVE_DELAY = 300

function start() {
  const container = document.getElementById('map')
  let map
  try {
    map = createMap(container, loadView(store))
  } catch (err) {
    container.textContent = NO_WEBGL
    console.error(err)
    return
  }

  map.on('error', (e) => {
    if (map.isStyleLoaded()) return
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
  render(<Places map={map} />, document.getElementById('panel'))

  window.mapper = { map }
}

start()
