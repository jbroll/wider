import { signal } from '@preact/signals'

import { GROUPS, DEFAULT_COLORS } from './colors.js'

export const colors = signal(DEFAULT_COLORS)

function black() {
  const out = {}
  for (const g of GROUPS) out[g.id] = '#000000'
  return out
}

// What the current style paints each group, so an unset swatch opens on what
// is actually drawn rather than on black.
export const styleColors = signal(black())

// The styles write colors in every CSS form and <input type="color"> takes
// only #rrggbb, so let the browser parse. See docs/architecture.md.
export function toHex(css) {
  const el = document.createElement('span')
  el.style.color = css
  if (!el.style.color) return null
  el.style.display = 'none'
  document.body.appendChild(el)
  const computed = getComputedStyle(el).color
  el.remove()
  const m = /^rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(computed)
  if (!m) return null
  return '#' + [1, 2, 3].map((i) => Number(m[i]).toString(16).padStart(2, '0')).join('')
}

export function seedColors(style) {
  const layers = style && Array.isArray(style.layers) ? style.layers : []
  const out = {}
  for (const g of GROUPS) {
    let hex = null
    for (const layer of layers) {
      if (layer.type !== 'symbol' || !layer.paint) continue
      if (!g.sourceLayers.includes(layer['source-layer'])) continue
      if (typeof layer.paint['text-color'] !== 'string') continue
      hex = toHex(layer.paint['text-color'])
      if (hex) break
    }
    out[g.id] = hex || '#000000'
  }
  return out
}

// <input type="color"> sanitizes anything but #rrggbb to black; expand the
// #rgb shorthand the store also accepts so a stored value still displays.
function forSwatch(hex) {
  return hex.length === 4 ? '#' + hex[1] + hex[1] + hex[2] + hex[2] + hex[3] + hex[3] : hex
}

// onPreview runs at pointer rate while the dialog is open: signal only, no
// persistence. onCommit runs once, on change or on the clear click: persist.
export function Pickers({ onPreview, onCommit }) {
  const chosen = colors.value
  const seeded = styleColors.value
  return (
    <div id="colors">
      {GROUPS.map((g) => {
        const c = chosen[g.id]
        return (
          <div class="color-row" key={g.id}>
            <span class="color-label">{g.label}</span>
            <input
              type="color"
              class="color-swatch"
              data-color={g.id}
              title={g.label + ' label color'}
              value={(c && forSwatch(c)) || seeded[g.id]}
              onInput={(e) => onPreview({ ...colors.value, [g.id]: e.currentTarget.value })}
              onChange={(e) => onCommit({ ...colors.value, [g.id]: e.currentTarget.value })}
            />
            <button
              class="color-clear"
              data-color={g.id}
              title={'Back to the style’s ' + g.label + ' color'}
              disabled={!c}
              onClick={() => onCommit({ ...colors.value, [g.id]: null })}
            >
              ×
            </button>
          </div>
        )
      })}
    </div>
  )
}
