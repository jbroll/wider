import { signal } from '@preact/signals'

import { DEFAULT_PINS, DEFAULT_PIN_TEXT, ICON_MIN_SCALE, loadPins, savePins, pinCss } from './pins.js'
import { forSwatch } from './colors.jsx'
import { ScaleRow } from './tweaks.jsx'

// What the default background shows in the swatch: its color without the alpha
// <input type="color"> cannot hold.
const DEFAULT_PIN_SWATCH = '#1c1c1c'

export const pins = signal(DEFAULT_PINS)

let store = null
let committed = DEFAULT_PINS

// The markers are a MapLibre DOM overlay, so these reach them through custom
// properties on the root, never through setStyle.
function show(next) {
  pins.value = next
  const root = document.documentElement.style
  for (const [name, value] of Object.entries(pinCss(next))) root.setProperty(name, value)
}

export function initPins(s) {
  store = s
  committed = loadPins(store)
  show(committed)
}

function preview(field, value) {
  show({ ...committed, [field]: value })
}

function commit(field, value) {
  committed = savePins(store, { ...committed, [field]: value })
  show(committed)
}

function ColorRow({ field, label, value, fallback }) {
  const hex = value && value !== 'transparent' ? forSwatch(value) : fallback
  return (
    <div class="color-row">
      <span class="color-label">{label}</span>
      <input
        type="color"
        class="color-swatch"
        data-color={'pin-' + field}
        title={'Pin label ' + field + ' color'}
        value={hex}
        onInput={(e) => preview(field, e.currentTarget.value)}
        onChange={(e) => commit(field, e.currentTarget.value)}
      />
      <button
        class="color-clear"
        data-color={'pin-' + field}
        title={'Back to the default pin label ' + field}
        disabled={!value}
        onClick={() => commit(field, null)}
      >
        ×
      </button>
    </div>
  )
}

export function PinControls() {
  const p = pins.value
  const transparent = p.background === 'transparent'
  return (
    <div id="pins">
      <div class="pins-heading">Pin labels</div>
      <ScaleRow
        id="pin-icon"
        label="Icon"
        value={p.iconScale}
        min={ICON_MIN_SCALE}
        less="Smaller pin icons"
        more="Larger pin icons"
        pick={(v) => commit('iconScale', v)}
      />
      <ScaleRow
        id="pin-label"
        label="Label"
        value={p.scale}
        less="Smaller pin labels"
        more="Larger pin labels"
        pick={(v) => commit('scale', v)}
      />
      <ColorRow field="text" label="Text" value={p.text} fallback={DEFAULT_PIN_TEXT} />
      <ColorRow field="background" label="Background" value={p.background} fallback={DEFAULT_PIN_SWATCH} />
      <div class="color-row">
        <span class="color-label" />
        <button
          class="pin-none"
          title="No background behind pin labels"
          aria-pressed={transparent}
          onClick={() => commit('background', transparent ? null : 'transparent')}
        >
          No background
        </button>
      </div>
    </div>
  )
}
