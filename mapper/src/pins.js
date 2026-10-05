import { validateScale } from './tweaks.js'
import { validateColor, haloFor } from './colors.js'

export const PINS_KEY = 'mapper.pins'

// `scale` sizes the name label and `iconScale` the marker icon.
export const DEFAULT_PINS = { scale: 1, iconScale: 1, text: null, background: null }

export const ICON_MIN_SCALE = 0.5

export const DEFAULT_PIN_TEXT = '#ffffff'
export const DEFAULT_PIN_BACKGROUND = 'rgba(28, 28, 28, 0.82)'

function validateBackground(value) {
  return value === 'transparent' ? value : validateColor(value)
}

// Per field, like validateColors: a bad text color must not reset the size.
export function validatePins(value) {
  const ok = value && typeof value === 'object' && !Array.isArray(value)
  if (!ok) return { ...DEFAULT_PINS }
  return {
    scale: validateScale(value.scale) || DEFAULT_PINS.scale,
    iconScale: validateScale(value.iconScale, ICON_MIN_SCALE) || DEFAULT_PINS.iconScale,
    text: validateColor(value.text),
    background: validateBackground(value.background),
  }
}

export function parsePins(raw) {
  if (typeof raw !== 'string') return { ...DEFAULT_PINS }
  try {
    return validatePins(JSON.parse(raw))
  } catch {
    return { ...DEFAULT_PINS }
  }
}

export function loadPins(store) {
  return parsePins(store.getItem(PINS_KEY))
}

export function savePins(store, pins) {
  const clean = validatePins(pins)
  store.setItem(PINS_KEY, JSON.stringify(clean))
  return clean
}

// With no background behind it the label sits straight on the map, so it
// gets a one-pixel outline in whichever of black or white contrasts.
function outline(color) {
  return ['-1px -1px', '1px -1px', '-1px 1px', '1px 1px'].map((o) => o + ' 0 ' + color).join(', ')
}

export function pinCss(pins) {
  const { scale, iconScale, text, background } = validatePins(pins)
  const textColor = text || DEFAULT_PIN_TEXT
  return {
    '--pin-scale': String(scale),
    '--icon-scale': String(iconScale),
    '--pin-text': textColor,
    '--pin-background': background || DEFAULT_PIN_BACKGROUND,
    '--pin-halo': background === 'transparent' ? outline(haloFor(textColor)) : 'none',
  }
}
