import { signal } from '@preact/signals'

import { TEXT_SCALES, BUILDING_ZOOMS, DEFAULT_TWEAKS } from './tweaks.js'

export const tweaks = signal(DEFAULT_TWEAKS)

function Row({ id, label, notches, value, text, less, more, pick }) {
  const i = notches.indexOf(value)
  return (
    <div class="tweak-row">
      <span class="tweak-label">{label}</span>
      <button
        class="tweak-down"
        data-tweak={id}
        title={less}
        disabled={i <= 0}
        onClick={() => pick(notches[i - 1])}
      >
        −
      </button>
      <span class="tweak-value" data-tweak={id}>{text}</span>
      <button
        class="tweak-up"
        data-tweak={id}
        title={more}
        disabled={i >= notches.length - 1}
        onClick={() => pick(notches[i + 1])}
      >
        +
      </button>
    </div>
  )
}

export function Steppers({ onChange }) {
  const t = tweaks.value
  return (
    <div id="tweaks">
      <Row
        id="text"
        label="Text"
        notches={TEXT_SCALES}
        value={t.textScale}
        text={Math.round(t.textScale * 100) + '%'}
        less="Smaller labels"
        more="Larger labels"
        pick={(v) => onChange({ ...t, textScale: v })}
      />
      <Row
        id="buildings"
        label="Buildings"
        notches={BUILDING_ZOOMS}
        value={t.buildingMinZoom}
        text={String(t.buildingMinZoom)}
        less="Buildings from further out"
        more="Buildings only closer in"
        pick={(v) => onChange({ ...t, buildingMinZoom: v })}
      />
    </div>
  )
}
