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
export async function switchStyle(map, store, id) {
  if (id === current.value) return true
  const token = ++switchToken
  let style
  try {
    const res = await fetch(styleUrl(id))
    if (!res.ok) throw new Error('HTTP ' + res.status)
    style = await res.json()
    if (token !== switchToken) return false
    map.setStyle(style)
  } catch (err) {
    if (token !== switchToken) return false
    console.error(err)
    toast('Could not load the ' + id + ' style.')
    return false
  }
  current.value = id
  saveStyle(store, id)
  return true
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
  return message.value ? <div id="toast">{message.value}</div> : null
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
