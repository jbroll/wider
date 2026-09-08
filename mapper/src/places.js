export const PLACES_KEY = 'mapper.places'

const num = (v) => typeof v === 'number' && Number.isFinite(v)

export function validatePlace(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const { id, name, lat, lon, zoom, bearing } = value
  if (typeof id !== 'string' || id === '') return null
  if (typeof name !== 'string') return null
  if (!num(lat) || lat < -90 || lat > 90) return null
  if (!num(lon) || lon < -180 || lon > 180) return null
  if (!num(zoom) || zoom < 0 || zoom > 24) return null
  if (!num(bearing)) return null
  return { id, name, lat, lon, zoom, bearing: ((bearing % 360) + 360) % 360 }
}

export function parsePlaces(raw) {
  if (typeof raw !== 'string') return []
  let value
  try {
    value = JSON.parse(raw)
  } catch {
    return []
  }
  if (!Array.isArray(value)) return []
  return value.map(validatePlace).filter(Boolean)
}

export function loadPlaces(store) {
  return parsePlaces(store.getItem(PLACES_KEY))
}

export function savePlaces(store, places) {
  const clean = places.map(validatePlace).filter(Boolean)
  store.setItem(PLACES_KEY, JSON.stringify(clean))
  return clean
}

export function newId() {
  return 'p' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

export function addPlace(places, place) {
  const clean = validatePlace(place)
  return clean ? [...places, clean] : [...places]
}

export function removePlace(places, id) {
  return places.filter((p) => p.id !== id)
}

export function renamePlace(places, id, name) {
  return places.map((p) => (p.id === id ? { ...p, name } : p))
}
