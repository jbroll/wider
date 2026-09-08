export const VIEW_KEY = 'mapper.view'

export const DEFAULT_VIEW = { center: [-98.5795, 39.8283], zoom: 3.5, bearing: 0, pitch: 0 }

const num = (v) => typeof v === 'number' && Number.isFinite(v)

export function validateView(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const { center, zoom, bearing, pitch } = value
  if (!Array.isArray(center) || center.length !== 2) return null
  const [lon, lat] = center
  if (!num(lon) || lon < -180 || lon > 180) return null
  if (!num(lat) || lat < -90 || lat > 90) return null
  if (!num(zoom) || zoom < 0 || zoom > 24) return null
  if (!num(bearing) || bearing < -360 || bearing > 360) return null
  if (!num(pitch) || pitch < 0 || pitch > 85) return null
  return { center: [lon, lat], zoom, bearing: ((bearing % 360) + 360) % 360, pitch }
}

export function parseView(raw) {
  if (typeof raw !== 'string') return DEFAULT_VIEW
  let value
  try {
    value = JSON.parse(raw)
  } catch {
    return DEFAULT_VIEW
  }
  return validateView(value) || DEFAULT_VIEW
}

export function loadView(store) {
  return parseView(store.getItem(VIEW_KEY))
}

export function saveView(store, view) {
  const clean = validateView(view)
  if (clean) store.setItem(VIEW_KEY, JSON.stringify(clean))
  return clean
}
