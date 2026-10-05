import { VIEW_KEY, validateView } from './view.js'
import { STYLE_KEY, validateStyleId } from './styles.js'
import { TWEAKS_KEY, validateTweaks } from './tweaks.js'
import { COLORS_KEY, validateColors } from './colors.js'
import { PINS_KEY, validatePins } from './pins.js'
import { PLACES_KEY, validatePlaces } from './places.js'
import { ROUTE_PREF_KEY, validateRoutePref, ROUTE_SELECTED_KEY, validateRouteSelected } from './route.js'

export const APP = 'mapper'
export const VERSION = 1

const isObject = (v) => Boolean(v) && typeof v === 'object' && !Array.isArray(v)

// validateColors and validatePins never fail: they fall back per field. A
// value that is not an object at all would load as all defaults, so it fails.
const objectOf = (validate) => (v) => (isObject(v) ? validate(v) : null)

// One entry per row of the Persistence table in docs/architecture.md, which
// test/backup.test.js checks. `validate` returns the value to store, or null.
export const KEYS = [
  { key: VIEW_KEY, label: 'view', json: true, validate: validateView },
  { key: STYLE_KEY, label: 'map style', json: false, validate: validateStyleId },
  { key: TWEAKS_KEY, label: 'Text and Buildings', json: true, validate: validateTweaks },
  { key: COLORS_KEY, label: 'label colors', json: true, validate: objectOf(validateColors) },
  { key: PINS_KEY, label: 'pin labels', json: true, validate: objectOf(validatePins) },
  { key: PLACES_KEY, label: 'places', json: true, validate: validatePlaces },
  { key: ROUTE_PREF_KEY, label: 'route preference', json: false, validate: validateRoutePref },
  { key: ROUTE_SELECTED_KEY, label: 'route selection', json: true, validate: validateRouteSelected },
]

export const NOT_JSON = 'That file is not valid JSON.'
export const NOT_MAPPER = 'That file is not a mapper export.'

function decode(entry, raw) {
  if (!entry.json) return entry.validate(raw)
  try {
    return entry.validate(JSON.parse(raw))
  } catch {
    return null
  }
}

// A stored value that would load as its fallback is left out, so an export
// never carries a value an import would skip.
export function buildExport(store, now = new Date()) {
  const data = {}
  for (const entry of KEYS) {
    const raw = store.getItem(entry.key)
    if (raw === null) continue
    const value = decode(entry, raw)
    if (value !== null) data[entry.key] = value
  }
  return { app: APP, version: VERSION, exported: now.toISOString(), data }
}

const pad = (n) => String(n).padStart(2, '0')

export function exportName(now = new Date()) {
  return 'mapper-' + now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate()) + '.json'
}

// Returns { error } when the whole file is rejected, otherwise { writes,
// skipped }: what applyImport will store, and the keys whose values failed.
export function parseImport(text) {
  let doc
  try {
    doc = JSON.parse(text)
  } catch {
    return { error: NOT_JSON }
  }
  if (!isObject(doc) || doc.app !== APP) return { error: NOT_MAPPER }
  if (doc.version !== VERSION) {
    return { error: 'Unsupported mapper export version: ' + JSON.stringify(doc.version ?? null) + '.' }
  }
  if (!isObject(doc.data)) return { error: NOT_MAPPER }
  const writes = []
  const skipped = []
  for (const entry of KEYS) {
    if (!Object.hasOwn(doc.data, entry.key)) continue
    const value = entry.validate(doc.data[entry.key])
    if (value === null) {
      skipped.push({ key: entry.key, label: entry.label })
      continue
    }
    writes.push({
      key: entry.key,
      label: entry.label,
      raw: entry.json ? JSON.stringify(value) : value,
    })
  }
  return { writes, skipped }
}

export function applyImport(store, writes) {
  for (const w of writes) store.setItem(w.key, w.raw)
}

function list(items) {
  const labels = items.map((i) => i.label)
  if (labels.length < 2) return labels.join('')
  return labels.slice(0, -1).join(', ') + ' and ' + labels[labels.length - 1]
}

const skippedText = ({ skipped }) => (skipped.length ? ' Skipped as invalid: ' + list(skipped) + '.' : '')

export function confirmText(result, fileName) {
  return 'Replace the saved ' + list(result.writes) + ' with the ones in ' + fileName + '?' +
    skippedText(result) + ' The page reloads afterwards.'
}

export function importedText(result) {
  return 'Imported ' + list(result.writes) + '.' + skippedText(result)
}

export function nothingText(result, fileName) {
  return 'Nothing to import from ' + fileName + '.' + skippedText(result)
}
