export const TWEAKS_KEY = 'mapper.tweaks'

export const TEXT_SCALES = [1, 1.1, 1.2, 1.3, 1.4, 1.5]
export const BUILDING_ZOOMS = [13, 14, 15, 16]

export const DEFAULT_TWEAKS = { textScale: TEXT_SCALES[0], buildingMinZoom: BUILDING_ZOOMS[0] }

export function validateTweaks(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const { textScale, buildingMinZoom } = value
  if (!TEXT_SCALES.includes(textScale)) return null
  if (!BUILDING_ZOOMS.includes(buildingMinZoom)) return null
  return { textScale, buildingMinZoom }
}

export function parseTweaks(raw) {
  if (typeof raw !== 'string') return DEFAULT_TWEAKS
  let value
  try {
    value = JSON.parse(raw)
  } catch {
    return DEFAULT_TWEAKS
  }
  return validateTweaks(value) || DEFAULT_TWEAKS
}

export function loadTweaks(store) {
  return parseTweaks(store.getItem(TWEAKS_KEY))
}

export function saveTweaks(store, tweaks) {
  const clean = validateTweaks(tweaks)
  if (clean) store.setItem(TWEAKS_KEY, JSON.stringify(clean))
  return clean
}

// In a flat ["interpolate", ["linear"], ["zoom"], z1, s1, z2, s2, ...] the
// outputs sit at the even indexes from 4 up and the zoom stops at the odd ones.
// No style nests an expression under an output, so anything else is left alone.
function scaleTextSize(size, scale) {
  if (typeof size === 'number') return size * scale
  if (!Array.isArray(size) || size[0] !== 'interpolate' || size.length < 5) return size
  const out = size.slice()
  for (let i = 4; i < out.length; i += 2) {
    if (typeof out[i] !== 'number') return size
    out[i] = out[i] * scale
  }
  return out
}

function scaleLayer(layer, scale) {
  if (scale === 1) return layer
  if (layer.type !== 'symbol' || !layer.layout) return layer
  const size = scaleTextSize(layer.layout['text-size'], scale)
  if (size === layer.layout['text-size']) return layer
  return { ...layer, layout: { ...layer.layout, 'text-size': size } }
}

// Returns a new style. mapper re-transforms the style it holds as fetched on
// every change, so mutating the input would compound scale on scale.
export function applyTweaks(style, tweaks) {
  const { textScale, buildingMinZoom } = validateTweaks(tweaks) || DEFAULT_TWEAKS
  if (!style || !Array.isArray(style.layers)) return style
  const layers = []
  for (const layer of style.layers) {
    if (layer['source-layer'] !== 'building') {
      layers.push(scaleLayer(layer, textScale))
      continue
    }
    if (typeof layer.maxzoom === 'number' && layer.maxzoom <= buildingMinZoom) continue
    const scaled = scaleLayer(layer, textScale)
    const minzoom = Math.max(buildingMinZoom, typeof scaled.minzoom === 'number' ? scaled.minzoom : 0)
    layers.push(minzoom === scaled.minzoom ? scaled : { ...scaled, minzoom })
  }
  return { ...style, layers }
}
