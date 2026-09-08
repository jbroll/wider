import maplibregl from 'maplibre-gl'

export function createMap(container, view, style) {
  const map = new maplibregl.Map({
    container,
    style,
    center: view.center,
    zoom: view.zoom,
    bearing: view.bearing,
    pitch: view.pitch,
    attributionControl: { compact: true },
  })
  map.addControl(new maplibregl.NavigationControl({ showCompass: true, visualizePitch: true }), 'top-right')
  return map
}
