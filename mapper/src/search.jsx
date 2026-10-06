import { signal } from '@preact/signals'

import { toast } from './styles.jsx'
import { MIN_CHARS, autocompleteUrl, parseResults, zoomFor } from './search.js'

const SEARCH_DELAY = 300

const UNREACHABLE = 'Could not reach the geocoder.'

// null is a closed list; an empty array is a finished search with no matches.
const results = signal(null)
const active = signal(-1)

let timer = 0
let token = 0

async function run(map, text) {
  const t = ++token
  const c = map.getCenter()
  let json
  try {
    const res = await fetch(autocompleteUrl(text, window.location.search, [c.lng, c.lat]))
    if (t !== token) return
    if (!res.ok) throw new Error('HTTP ' + res.status)
    json = await res.json()
  } catch (err) {
    if (t !== token) return
    console.error(err)
    results.value = null
    toast(UNREACHABLE)
    return
  }
  if (t !== token) return
  results.value = parseResults(json)
  active.value = -1
}

// Bumping the token drops any response still in flight, so a late answer
// cannot reopen the list after a pick or an Escape.
function close() {
  clearTimeout(timer)
  token++
  results.value = null
  active.value = -1
}

export function Search({ map }) {
  const onInput = (e) => {
    const text = e.currentTarget.value.trim()
    clearTimeout(timer)
    if (text.length < MIN_CHARS) {
      close()
      return
    }
    timer = setTimeout(() => run(map, text), SEARCH_DELAY)
  }

  const pick = (input, r) => {
    close()
    input.value = r.label
    map.flyTo({ center: [r.lon, r.lat], zoom: zoomFor(r.layer) })
  }

  const onKeyDown = (e) => {
    const list = results.value
    if (e.key === 'Escape') {
      close()
      return
    }
    if (!list || list.length === 0) return
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      active.value = (active.value + 1) % list.length
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      active.value = (active.value - 1 + list.length) % list.length
    } else if (e.key === 'Enter') {
      pick(e.currentTarget, list[Math.max(active.value, 0)])
    }
  }

  const list = results.value
  return (
    <div id="search-box">
      <input
        id="search"
        type="search"
        placeholder="Search address"
        autocomplete="off"
        role="combobox"
        aria-expanded={list !== null}
        aria-controls="search-results"
        aria-activedescendant={active.value >= 0 ? 'search-result-' + active.value : undefined}
        onInput={onInput}
        onKeyDown={onKeyDown}
        onBlur={close}
      />
      {list && (
        // mousedown would blur the input and close the list before the click lands.
        <ul id="search-results" role="listbox" onMouseDown={(e) => e.preventDefault()}>
          {list.length === 0 && <li class="search-empty">No matches</li>}
          {list.map((r, i) => (
            <li
              key={i}
              id={'search-result-' + i}
              role="option"
              aria-selected={i === active.value}
              class="search-result"
              onClick={() => pick(document.getElementById('search'), r)}
            >
              {r.label}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
