export const COLORS_KEY = 'mapper.colors'

// Airport names sit with the POIs and river names with the water because that
// is how the styles color them: Liberty gives aerodrome_label the same #666 as
// its poi layers, and waterway the #74aee9 beside water_name's #495e91.
export const GROUPS = [
  { id: 'places', label: 'Places', sourceLayers: ['place'] },
  { id: 'streets', label: 'Streets', sourceLayers: ['transportation_name'] },
  { id: 'pois', label: 'POIs', sourceLayers: ['poi', 'aerodrome_label'] },
  { id: 'water', label: 'Water', sourceLayers: ['water_name', 'waterway'] },
]

export const DEFAULT_COLORS = { places: null, streets: null, pois: null, water: null }

const GROUP_OF = new Map()
for (const g of GROUPS) for (const name of g.sourceLayers) GROUP_OF.set(name, g.id)

const HEX = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i

export function validateColor(value) {
  return typeof value === 'string' && HEX.test(value) ? value : null
}

// Per group rather than all-or-nothing like validateTweaks: four independent
// colors, so a malformed one must not clear the other three.
export function validateColors(value) {
  const ok = value && typeof value === 'object' && !Array.isArray(value)
  const out = {}
  for (const g of GROUPS) out[g.id] = ok ? validateColor(value[g.id]) : null
  return out
}

export function parseColors(raw) {
  if (typeof raw !== 'string') return { ...DEFAULT_COLORS }
  try {
    return validateColors(JSON.parse(raw))
  } catch {
    return { ...DEFAULT_COLORS }
  }
}

export function loadColors(store) {
  return parseColors(store.getItem(COLORS_KEY))
}

export function saveColors(store, colors) {
  const clean = validateColors(colors)
  store.setItem(COLORS_KEY, JSON.stringify(clean))
  return clean
}

// WCAG relative luminance.
export function luminance(hex) {
  const h = hex.slice(1)
  const full = h.length === 3 ? h[0] + h[0] + h[1] + h[1] + h[2] + h[2] : h
  const chan = (i) => {
    const c = parseInt(full.slice(i * 2, i * 2 + 2), 16) / 255
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * chan(0) + 0.7152 * chan(1) + 0.0722 * chan(2)
}

export function haloFor(hex) {
  return luminance(hex) < 0.5 ? '#ffffff' : '#000000'
}

// MapLibre's default halo width is 0, so a halo color set on a layer that
// declares no width would be invisible. An existing width is left alone: the
// styles' 0.5 to 2 is what separates a country name from a town name.
function recolor(layer, color) {
  const paint = { ...layer.paint, 'text-color': color, 'text-halo-color': haloFor(color) }
  if (paint['text-halo-width'] === undefined) paint['text-halo-width'] = 1
  return { ...layer, paint }
}

// Returns a new style, like applyTweaks: mapper re-transforms the style it
// holds as fetched on every change.
//
// A symbol layer with no text-color draws no text of its own, which is what
// excludes the route shields - their number is on a sprite badge - with no
// special case for them.
export function applyColors(style, colors) {
  const clean = validateColors(colors)
  if (!style || !Array.isArray(style.layers)) return style
  const layers = style.layers.map((layer) => {
    if (layer.type !== 'symbol' || !layer.paint) return layer
    if (layer.paint['text-color'] === undefined) return layer
    const group = GROUP_OF.get(layer['source-layer'])
    const color = group ? clean[group] : null
    return color ? recolor(layer, color) : layer
  })
  return { ...style, layers }
}
