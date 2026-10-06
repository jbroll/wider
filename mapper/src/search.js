// Relative, like ORS_BASE_URL: /geocode from serve.js, /mapper/geocode behind
// Apache. Both proxy it to over-coder.
export const GEOCODE_BASE_URL = 'geocode'

// over-coder answers nothing below three characters.
export const MIN_CHARS = 3
export const RESULT_COUNT = 8

const ZOOMS = { address: 17, street: 15 }
const DEFAULT_ZOOM = 12

export function autocompleteUrl(text, search, [lon, lat]) {
  const params = new URLSearchParams({
    text,
    size: String(RESULT_COUNT),
    'focus.point.lat': String(lat),
    'focus.point.lon': String(lon),
  })
  const token = new URLSearchParams(search).get('token')
  if (token) params.set('token', token)
  return GEOCODE_BASE_URL + '/v1/autocomplete?' + params
}

export function parseResults(json) {
  const features = json && Array.isArray(json.features) ? json.features : []
  const out = []
  for (const f of features) {
    const coords = f && f.geometry && f.geometry.coordinates
    const props = (f && f.properties) || {}
    const label = props.label || props.name
    if (!Array.isArray(coords) || !Number.isFinite(coords[0]) || !Number.isFinite(coords[1]) || !label) continue
    out.push({ label, layer: props.layer, lon: coords[0], lat: coords[1] })
  }
  return out
}

export function zoomFor(layer) {
  return ZOOMS[layer] || DEFAULT_ZOOM
}
