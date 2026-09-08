export const STYLE_KEY = 'mapper.style'

export const STYLES = ['liberty', 'bright', 'positron', 'dark', 'fiord'].map((id) => ({
  id,
  name: id[0].toUpperCase() + id.slice(1),
  url: 'https://tiles.openfreemap.org/styles/' + id,
}))

export const DEFAULT_STYLE_ID = 'liberty'

export function validateStyleId(value) {
  if (typeof value !== 'string') return null
  return STYLES.some((s) => s.id === value) ? value : null
}

export function styleUrl(id) {
  const wanted = validateStyleId(id) || DEFAULT_STYLE_ID
  return STYLES.find((s) => s.id === wanted).url
}

export function loadStyle(store) {
  return validateStyleId(store.getItem(STYLE_KEY)) || DEFAULT_STYLE_ID
}

export function saveStyle(store, id) {
  const clean = validateStyleId(id)
  if (clean) store.setItem(STYLE_KEY, clean)
  return clean
}
