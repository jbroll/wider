export const ORS_BASE_URL = 'http://192.168.1.169:8082/ors'
export const PROFILE = 'foot-walking'

export const ROUTE_SOURCE_ID = 'mapper-route'
export const ROUTE_LAYER_ID = 'mapper-route-line'

export function directionsUrl() {
  return ORS_BASE_URL + '/v2/directions/' + PROFILE + '/geojson'
}

// ORS wants [lon, lat] pairs in the order the route should visit them.
export function buildBody(points) {
  return { coordinates: points.map((p) => [p.lon, p.lat]) }
}

export function parseRoute(json) {
  const feature = json && Array.isArray(json.features) ? json.features[0] : null
  if (!feature || !feature.geometry) return null
  const segments = feature.properties && feature.properties.segments
  const seg = (Array.isArray(segments) && segments[0]) || {}
  return {
    geometry: feature.geometry,
    distance: typeof seg.distance === 'number' ? seg.distance : null,
    duration: typeof seg.duration === 'number' ? seg.duration : null,
  }
}

export function formatDistance(metres) {
  if (typeof metres !== 'number') return ''
  return metres >= 1000 ? (metres / 1000).toFixed(1) + ' km' : Math.round(metres) + ' m'
}

export function formatDuration(seconds) {
  if (typeof seconds !== 'number') return ''
  return Math.max(1, Math.round(seconds / 60)) + ' min'
}

// Returns a new style, like applyTweaks and applyColors. A route with no
// geometry is the "no route" case, so the style comes back unchanged.
export function applyRoute(style, route) {
  if (!style || !Array.isArray(style.layers) || !route || !route.geometry) return style
  const source = {
    type: 'geojson',
    data: { type: 'Feature', geometry: route.geometry, properties: {} },
  }
  const layer = {
    id: ROUTE_LAYER_ID,
    type: 'line',
    source: ROUTE_SOURCE_ID,
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: {
      'line-color': '#4285f4',
      'line-width': 7,
      'line-opacity': 0.95,
      'line-dasharray': [0, 2],
    },
  }
  return {
    ...style,
    sources: { ...style.sources, [ROUTE_SOURCE_ID]: source },
    layers: [...style.layers.filter((l) => l.id !== ROUTE_LAYER_ID), layer],
  }
}
