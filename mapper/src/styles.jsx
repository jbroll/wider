import { render } from 'preact'
import { signal } from '@preact/signals'

import { STYLES, DEFAULT_STYLE_ID, loadStyle, saveStyle, styleUrl } from './styles.js'
import { loadTweaks, saveTweaks, applyTweaks } from './tweaks.js'
import { tweaks, Steppers } from './tweaks.jsx'
import { loadColors, saveColors, applyColors } from './colors.js'
import { colors, styleColors, seedColors, Pickers } from './colors.jsx'

const TOAST_MS = 4000

const current = signal(DEFAULT_STYLE_ID)
const message = signal('')

let timer = 0
let switchToken = 0

// The style as fetched, untransformed. A stepper move re-transforms this same
// object rather than refetching, so the transform must not mutate it.
let fetched = null

// What the store holds. colors.value is the display-and-apply value and can
// hold an uncommitted preview; committed is merged into on commit and is what
// a commit persists, so a dismissed preview can never be spread by a later one.
let committed = null

// Both transforms read their values at the moment they apply, so a picker
// moved while a switch is in flight is carried by that switch when it lands.
const transform = (style) => applyColors(applyTweaks(style, tweaks.value), colors.value)

export function toast(text) {
  message.value = text
  clearTimeout(timer)
  timer = setTimeout(() => { message.value = '' }, TOAST_MS)
}

// Fetch before setStyle: a failed request must not tear down the running map.
// The token is bumped before the current-style early return, so clicking the
// current style still cancels whatever switch is in flight.
export async function switchStyle(map, store, id) {
  const token = ++switchToken
  if (id === current.value) return true
  let style
  try {
    const res = await fetch(styleUrl(id))
    if (!res.ok) throw new Error('HTTP ' + res.status)
    style = await res.json()
  } catch (err) {
    if (token !== switchToken) return false
    console.error(err)
    const name = (STYLES.find((s) => s.id === id) || {}).name || id
    toast('Could not load the ' + name + ' style.')
    return false
  }
  if (token !== switchToken) return false
  fetched = style
  styleColors.value = seedColors(style)
  map.setStyle(transform(style))
  // styledata here is not a load confirmation, just the "style changed" tick
  // MapLibre fires once setState accepts the body. A body setState rejects as
  // invalid fires no styledata, so nothing gets persisted for it - that's the
  // one failure this wait actually screens out. A broken sprite fires
  // styledata anyway; see docs/backlog.md.
  return new Promise((resolve) => {
    map.once('styledata', () => {
      if (token !== switchToken) { resolve(false); return }
      current.value = id
      saveStyle(store, id)
      resolve(true)
    })
  })
}

function Buttons({ map, store }) {
  return STYLES.map((s) => (
    <button
      key={s.id}
      class={'style-button' + (current.value === s.id ? ' current' : '')}
      data-style={s.id}
      aria-pressed={current.value === s.id}
      title={s.name + ' map style'}
      onClick={() => switchStyle(map, store, s.id)}
    >
      {s.name}
    </button>
  ))
}

function Toast() {
  return <div id="toast" aria-live="polite" hidden={!message.value}>{message.value}</div>
}

export function addStyleControl(map, store, style) {
  current.value = loadStyle(store)
  tweaks.value = loadTweaks(store)
  colors.value = loadColors(store)
  committed = colors.value
  fetched = style
  styleColors.value = seedColors(style)

  const host = document.createElement('div')
  document.body.appendChild(host)
  render(<Toast />, host)

  const change = (next) => {
    const clean = saveTweaks(store, next)
    if (!clean) return
    tweaks.value = clean
    if (fetched) map.setStyle(transform(fetched))
  }

  // The color dialog fires input continuously while dragging, so the map
  // update is coalesced to one per frame; the store write waits for commit.
  let previewFrame = 0

  const previewColors = (id, value) => {
    colors.value = { ...committed, [id]: value }
    if (previewFrame) return
    previewFrame = requestAnimationFrame(() => {
      previewFrame = 0
      if (fetched) map.setStyle(transform(fetched))
    })
  }

  const changeColors = (id, value) => {
    if (previewFrame) {
      cancelAnimationFrame(previewFrame)
      previewFrame = 0
    }
    committed = saveColors(store, { ...committed, [id]: value })
    colors.value = committed
    if (fetched) map.setStyle(transform(fetched))
  }

  map.addControl({
    onAdd() {
      const el = document.createElement('div')
      el.id = 'styles'
      el.className = 'maplibregl-ctrl maplibregl-ctrl-group'
      render(
        <>
          <Buttons map={map} store={store} />
          <div class="tweak-divider" />
          <Steppers onChange={change} />
          <div class="tweak-divider" />
          <Pickers onPreview={previewColors} onCommit={changeColors} />
        </>,
        el,
      )
      return el
    },
    onRemove() {
      if (previewFrame) cancelAnimationFrame(previewFrame)
    },
  }, 'top-right')
}
