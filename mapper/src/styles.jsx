import { render } from 'preact'
import { signal } from '@preact/signals'

import { STYLES, DEFAULT_STYLE_ID, loadStyle, saveStyle, styleUrl } from './styles.js'

const TOAST_MS = 4000

const current = signal(DEFAULT_STYLE_ID)
const message = signal('')

let timer = 0
let switchToken = 0

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
  map.setStyle(style)
  // setStyle applying is not the same as the style loading: a body that
  // parses but fails validation, or a broken sprite, still needs a real
  // load signal before the switch counts as done.
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
  return message.value ? <div id="toast" aria-live="polite">{message.value}</div> : null
}

export function addStyleControl(map, store) {
  current.value = loadStyle(store)

  const host = document.createElement('div')
  document.body.appendChild(host)
  render(<Toast />, host)

  map.addControl({
    onAdd() {
      const el = document.createElement('div')
      el.id = 'styles'
      el.className = 'maplibregl-ctrl maplibregl-ctrl-group'
      render(<Buttons map={map} store={store} />, el)
      return el
    },
    onRemove() {},
  }, 'top-right')
}
