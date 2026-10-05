export const PLACES_KEY = 'mapper.places'

// `pin` is MapLibre's own default marker; its emoji only stands in for it in
// the panel. `anchor` and `shift` (em, so it scales with the glyph) put the
// emoji's point of contact on the coordinate: Noto's flag pole stands a
// quarter em in from the glyph's left edge.
export const ICONS = [
  { id: 'pin', name: 'Pin', emoji: '📍', anchor: null, shift: 0 },
  { id: 'star', name: 'Star', emoji: '⭐', anchor: 'center', shift: 0 },
  { id: 'finish', name: 'Finish flag', emoji: '🏁', anchor: 'bottom-left', shift: -0.25 },
]

export const DEFAULT_ICON = 'pin'

export function iconFor(id) {
  return ICONS.find((i) => i.id === id) || ICONS.find((i) => i.id === DEFAULT_ICON)
}

const num = (v) => typeof v === 'number' && Number.isFinite(v)

export function validatePlace(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const { id, name, lat, lon, zoom, bearing, icon, hidden } = value
  if (typeof id !== 'string' || id === '') return null
  if (typeof name !== 'string') return null
  if (!num(lat) || lat < -90 || lat > 90) return null
  if (!num(lon) || lon < -180 || lon > 180) return null
  if (!num(zoom) || zoom < 0 || zoom > 24) return null
  if (!num(bearing)) return null
  return {
    id, name, lat, lon, zoom,
    bearing: ((bearing % 360) + 360) % 360,
    icon: iconFor(icon).id,
    hidden: hidden === true,
  }
}

// Null for anything but an array; inside one, invalid entries are dropped.
export function validatePlaces(value) {
  return Array.isArray(value) ? value.map(validatePlace).filter(Boolean) : null
}

export function parsePlaces(raw) {
  if (typeof raw !== 'string') return []
  let value
  try {
    value = JSON.parse(raw)
  } catch {
    return []
  }
  return validatePlaces(value) || []
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

export function setPlaceIcon(places, id, icon) {
  if (!ICONS.some((i) => i.id === icon)) return [...places]
  return places.map((p) => (p.id === id ? { ...p, icon } : p))
}

export function setPlaceHidden(places, id, hidden) {
  return places.map((p) => (p.id === id ? { ...p, hidden: hidden === true } : p))
}

export function movePlace(places, id, lat, lon) {
  return places.map((p) => {
    if (p.id !== id) return p
    const moved = validatePlace({ ...p, lat, lon })
    return moved || p
  })
}

// Moves the place `id` to just before `beforeId`; a `beforeId` that is
// missing or not found appends it at the end instead.
export function reorderPlace(places, id, beforeId) {
  if (id === beforeId) return [...places]
  const idx = places.findIndex((p) => p.id === id)
  if (idx < 0) return [...places]
  const item = places[idx]
  const rest = places.filter((p) => p.id !== id)
  const targetIdx = rest.findIndex((p) => p.id === beforeId)
  if (targetIdx < 0) return [...rest, item]
  rest.splice(targetIdx, 0, item)
  return rest
}
