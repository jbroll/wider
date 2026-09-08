import { createMap } from './map.js'
import { loadView, saveView } from './view.js'
import { render } from 'preact'
import { Places, attach } from './places.jsx'

const NO_WEBGL = 'This window cannot draw the map: WebGL is unavailable.'

const SAVE_DELAY = 300

function start() {
  const container = document.getElementById('map')
  let map
  try {
    map = createMap(container, loadView(window.localStorage))
  } catch (err) {
    container.textContent = NO_WEBGL
    console.error(err)
    return
  }

  let timer = 0
  map.on('moveend', () => {
    clearTimeout(timer)
    timer = setTimeout(() => saveView(window.localStorage, {
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
