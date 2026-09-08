# mapper text size and building zoom

mapper draws each style exactly as OpenFreeMap ships it. This adds two
steppers for adjusting the label size and the zoom at which buildings appear,
remembered across launches.

## The steppers

They sit in the existing style control, below a divider under the five style
buttons:

    Text        -  100%  +
    Buildings   -   13   +

`Text` scales every label in the style. Six notches: 100, 110, 120, 130, 140,
150 percent. `Buildings` sets the zoom below which buildings are not drawn.
Four notches: 13, 14, 15, 16.

Both default to the low end, so the first launch after this change looks the
way it looks today. At the `-` end of a range the `-` button is disabled, and
likewise for `+`.

## Remembering the choice

One key, `mapper.tweaks`, beside `mapper.view`, `mapper.places` and
`mapper.style`:

    {"textScale":1.2,"buildingMinZoom":15}

A value that is not one of the listed notches, a missing field, or a malformed
document falls back to the defaults. Validation lives in `tweaks.js` as pure
functions, tested without a browser, the same shape as `view.js`, `places.js`
and `styles.js`.

## The transform

`applyTweaks(style, tweaks)` returns a new style object. It must not mutate its
input: mapper keeps the style as fetched and re-transforms that same object on
every change, so a mutating transform would compound scale on scale.

### Text

Every layer of type `symbol` carries its size at `layout['text-size']`. Across
the five styles that value is one of three things:

- a plain number, which is multiplied by the scale
- a flat `["interpolate", ["linear"], ["zoom"], z1, s1, z2, s2, ...]`, whose
  outputs (`s1`, `s2`, ...) are multiplied and whose zoom stops are left alone
- absent, on the icon-only layers, which are left alone

No style has a nested expression under an interpolate output. Anything that is
not a number or a flat interpolate is left alone rather than guessed at.

### Buildings

A building layer is one whose `source-layer` is `building`. That matches every
building layer in all five styles, including Bright's second `building-top`,
and it is what the layer ids happen to agree with:

    liberty   building (fill, 13-14), building-3d (fill-extrusion, 14+)
    bright    building (fill), building-top (fill), neither with a zoom range
    positron  building (fill, 12+)
    dark      building (fill, 12+)
    fiord     building (fill, 12+)

The notch is a floor, not an assignment. A building layer's `minzoom` is raised
to it, and a building layer whose `maxzoom` is at or below the floor is dropped
from the style.

Dropping is what makes Liberty work. Its 2D `building` fill covers 13 to 14 and
`building-3d` takes over above 14, so a floor of 15 must remove the fill rather
than leave it with a `minzoom` above its own `maxzoom`.

At the default notch of 13 the floor changes nothing visible. Liberty already
starts at 13, and the three styles that declare 12 have no buildings to draw
there: the vector source carries none below 13.

## Flow

`main.jsx` fetches the startup style's JSON, runs it through `applyTweaks`, and
constructs the map with the resulting object. If that fetch fails it shows the
existing "This window cannot draw the map: the map style failed to load"
message. The `map.on('error')` handler stays as it is for the sprite and tile
errors it already sees, and a style body MapLibre rejects still reaches it,
because the map is constructed from an object through the validating path.

This is a change from loading the startup style by URL. There is no way around
it: MapLibre's `transformStyle` hook exists only on `setStyle`, not on the map
constructor, so a style the map loads by URL at startup cannot be transformed
on the way in.

`main.jsx` hands the fetched JSON to `addStyleControl`, which already owns
switching and now also holds the style as fetched. Moving a stepper saves the
new tweaks and re-applies that held style. No refetch.

The transform reads the tweak values at the moment it applies, not when the
click happened, so a stepper moved while a style switch is in flight is carried
by that switch when it lands.

## Files

    src/tweaks.js      the notches, validation, load/save, applyTweaks (pure)
    src/tweaks.jsx     the two stepper rows
    src/styles.jsx     holds the fetched style, re-applies on a stepper move,
                       renders the steppers below a divider
    src/main.jsx       fetches and transforms the startup style
    src/map.js         unchanged: it forwards whatever style it is given
    src/style.css      the divider and the stepper rows
    test/tweaks.test.js
    test/harness.js    a stub style the transform can be observed on
    test/map.spec.js   added specs

## Tests

`tweaks.test.js` covers the pure module: a plain `text-size` scales, an
interpolate's outputs scale while its zoom stops do not, an absent or
unrecognised `text-size` is left alone, a building layer's `minzoom` rises to
the floor, a building layer whose `maxzoom` is at or below the floor is
dropped, a non-building layer is untouched, the default tweaks leave a style
alone, the input object is not mutated, and the store round trip and its
fallbacks behave like the other three modules.

The Playwright stub currently has one background layer and no sources, so
nothing in it can show the transform. It gains a symbol layer with a numeric
`text-size`, a symbol layer with an interpolate, and a `building` fill on a
vector source declared with an inline `tiles` array, so no TileJSON is fetched.
The symbol layers carry no `text-field`, so no glyphs are fetched either, and
the `/data/` tile path is aborted the way the existing failed-tile spec already
does.

Playwright covers:

- stepping `Text` up changes a symbol layer's `text-size` in `map.getStyle()`
  and issues no style request
- stepping `Buildings` up changes the building layer's `minzoom`
- both settings survive a reload
- the `-` buttons are disabled at the low end and the `+` buttons at the high
  end
- switching style keeps the current tweaks applied

## Docs

`user-manual.md` gains the steppers beside the style buttons and the
`mapper.tweaks` key. `architecture.md` records that the startup style is now
fetched and transformed rather than loaded by URL, and why, and that the style
is held as fetched so a stepper move needs no refetch.

`backlog.md` has an entry reading "A control for how much the map draws when
zoomed out, and per-style memory of such overrides", which this builds half of.
Rewrite it to keep only the per-style half, and keep the note about the vector
source ending at zoom 14, which nothing here changes.

## Left out

Per-style memory of these settings. One setting shared by all five styles is a
statement about the screen, not about Liberty.

Icon sizes. `icon-size` scales independently of `text-size` and nothing asked
for it.
