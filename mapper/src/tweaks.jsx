import { signal } from '@preact/signals'

import { BUILDING_ZOOMS, DEFAULT_TWEAKS, stepScale } from './tweaks.js'

export const tweaks = signal(DEFAULT_TWEAKS)

// onLess and onMore are null where the range ends, which disables that
// button. A value can't stand in for that: Buildings uses null for Off.
function Row({ id, label, text, less, more, onLess, onMore }) {
  return (
    <div class="tweak-row">
      <span class="tweak-label">{label}</span>
      <button
        class="tweak-down"
        data-tweak={id}
        title={less}
        disabled={!onLess}
        onClick={onLess}
      >
        −
      </button>
      <span class="tweak-value" data-tweak={id}>{text}</span>
      <button
        class="tweak-up"
        data-tweak={id}
        title={more}
        disabled={!onMore}
        onClick={onMore}
      >
        +
      </button>
    </div>
  )
}

export function ScaleRow({ id, label, value, min = 1, less, more, pick }) {
  return (
    <Row
      id={id}
      label={label}
      text={Math.round(value * 100) + '%'}
      less={less}
      more={more}
      onLess={value > min ? () => pick(stepScale(value, -1, min)) : null}
      onMore={() => pick(stepScale(value, 1, min))}
    />
  )
}

function NotchRow({ notches, value, pick, ...rest }) {
  const i = notches.indexOf(value)
  return (
    <Row
      {...rest}
      onLess={i > 0 ? () => pick(notches[i - 1]) : null}
      onMore={i < notches.length - 1 ? () => pick(notches[i + 1]) : null}
    />
  )
}

export function Steppers({ onChange }) {
  const t = tweaks.value
  return (
    <div id="tweaks">
      <ScaleRow
        id="text"
        label="Text"
        value={t.textScale}
        less="Smaller labels"
        more="Larger labels"
        pick={(v) => onChange({ ...t, textScale: v })}
      />
      <NotchRow
        id="buildings"
        label="Buildings"
        notches={BUILDING_ZOOMS}
        value={t.buildingMinZoom}
        text={t.buildingMinZoom === null ? 'Off' : String(t.buildingMinZoom)}
        less="Buildings from further out"
        more="Buildings only closer in"
        pick={(v) => onChange({ ...t, buildingMinZoom: v })}
      />
    </div>
  )
}
