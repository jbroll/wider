# mapper label colors

mapper draws each style's labels in the colors the style ships. This adds four
color pickers, one per kind of label, remembered across launches.

## The groups

Six source-layers carry a `text-color` across the five styles. They fall into
four groups:

    Places    place
    Streets   transportation_name
    POIs      poi, aerodrome_label
    Water     water_name, waterway

Places, Streets and Water exist in all five styles. `poi` exists only in
Liberty and Bright; `aerodrome_label` also in Positron. A group whose
source-layers are absent from the current style draws nothing, and its picker
still shows and still stores a value. No picker is ever greyed out or hidden
for the current style.

Airport names join POIs because that is how the styles color them: Liberty
gives `aerodrome_label` the same `#666` as its four `poi` layers. River names
join Water for the same reason, `#74aee9` beside `water_name`'s `#495e91`.

## The transform

`applyColors(style, colors)` returns a new style object. Like `applyTweaks` it
must not mutate its input: mapper keeps the style as fetched and re-transforms
that same object on every change.

For each layer of type `symbol` that has a `text-color`, when its
`source-layer` belongs to a group whose color is set:

- `text-color` becomes the chosen color
- `text-halo-color` becomes `#ffffff` or `#000000`, whichever contrasts with
  the chosen color
- `text-halo-width` is set to `1` where it is absent, and left alone otherwise

A layer with no `text-color` is left alone. That is what excludes the route
shields: Liberty, Bright and Positron each carry `highway-shield-non-us`,
`highway-shield-us-interstate` and `road_shield_us` on `transportation_name`,
and none of them declares a `text-color`, because the number is drawn on a
sprite badge. No special case is needed for them. Fiord's `highway_ref` does
declare one and draws no sprite, so it is recolored like any other label.

Existing halo widths are preserved. The styles use 0.5, 1, 1.4, 1.5 and 2
deliberately, and flattening them to a single value would cost country names
the weight that separates them from town names.

The `1` is for two layers. Liberty's `highway-name-minor` and
`highway-name-major` already carry `text-halo-width: 1` with no halo color, and
MapLibre's default halo color is transparent, which is why they read as
halo-less today; setting the color alone gives them a halo. Only Dark's
`water_name` and `highway_name_motorway` declare no width at all, and
MapLibre's default width is 0, so without this clause their halo would be set
and invisible.

### Contrast

The halo is white under a dark color and black under a light one, decided by
WCAG relative luminance with a threshold of 0.5. Each channel is scaled to 0-1
and linearized, `c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4`, then
weighted `0.2126 R + 0.7152 G + 0.0722 B`. Below 0.5 the halo is `#ffffff`,
at or above it `#000000`.

This is a fixed rule with no control of its own. It exists so a chosen color
stays readable over whatever the style paints beneath it, not to be tuned.

### Not touched

`icon-color`. The POI glyphs and the black dot beside a city name keep the
color the style gives them, so a red Places label still carries a black dot.
Scoping this to icons is a separate feature.

## Remembering the choice

One key, `mapper.colors`, beside `mapper.view`, `mapper.places`,
`mapper.style` and `mapper.tweaks`:

    {"places":"#1a1a1a","streets":null,"pois":"#7a4f00","water":null}

A group whose value is `null`, missing, or not a color is untouched, and a bad
value in one group does not disturb the other three. Accepted values are `#rgb`
and `#rrggbb`, case-insensitive; `loadColors` returns all four keys with `null`
where a group is unset.

This per-group fallback deliberately differs from `mapper.tweaks`, where any
invalid field resets the whole document. All-or-nothing suits two coupled
notches and does not suit four independent colors. Keeping the two keys
separate also means a malformed color cannot reset the text size.

Validation lives in `colors.js` as pure functions, tested without a browser,
the same shape as `view.js`, `places.js`, `styles.js` and `tweaks.js`.

## The control

A third block in the style control, below a second divider under the two
steppers:

    Places      [swatch] ×
    Streets     [swatch] ×
    POIs        [swatch] ×
    Water       [swatch] ×

The swatch is an `<input type="color">`. When the group is set, its value is
the chosen color. When the group is unset it shows the color the current style
gives that group, read from the first layer of the group's source-layers that
declares a `text-color`, so the swatch opens on what is actually drawn rather
than on black. A group with no such layer in the current style shows
`#000000`.

Reading the style to seed a swatch is the control's only use of it. Nothing is
greyed out or hidden by what the style contains, and an unset swatch re-seeds
when the style changes, so switching from Liberty to Dark moves an unset
Streets swatch from `#666666` to `#504e4e`.

`<input type="color">` accepts only `#rrggbb`, and the styles give their colors
in every CSS form: `#666`, `#495e91`, `hsl(30,23%,62%)`, `rgba(80, 78, 78, 1)`,
`hsla(228,60%,21%,0.7)`. Rather than parse those, the seeding code assigns the
string to a detached element's `style.color` and reads `getComputedStyle` back,
which the browser normalizes to `rgb(r, g, b)`; converting that to `#rrggbb` is
arithmetic. An unparseable string leaves the property unset and falls back to
`#000000`.

This needs a DOM, so it lives in `colors.jsx` beside the component rather than
in the pure `colors.js`, and Playwright covers it rather than `node --test`.
The transform in `colors.js` stays pure and never converts anything: it only
ever writes the `#rgb` or `#rrggbb` the user picked.

`<input type="color">` has no unset state, so each row carries its own `×` to
clear that group back to the style's colors. The `×` is disabled while the
group is unset.

## Flow

`applyColors` runs on the output of `applyTweaks`, in both places a style is
applied: `main.jsx` at startup, and `styles.jsx` on a switch or a control move.
Both transforms read their values at the moment they apply, so a picker moved
while a style switch is in flight is carried by that switch when it lands.

`styles.jsx` already holds the style as fetched and already re-applies it on a
stepper move. A picker move takes the same path. No refetch.

## Files

    src/colors.js      the groups, validation, load/save, applyColors (pure)
    src/colors.jsx     the four picker rows
    src/styles.jsx     re-applies on a picker move, renders the rows below a
                       second divider
    src/main.jsx       composes applyColors over applyTweaks at startup
    src/tweaks.js      unchanged
    src/map.js         unchanged
    src/style.css      the second divider and the picker rows
    test/colors.test.js
    test/harness.js    stub layers per group
    test/map.spec.js   added specs

## Tests

`colors.test.js` covers the pure module: each group recolors its own
source-layers and no others, a layer with no `text-color` is left alone, a
shield layer is left alone, the halo flips at the luminance threshold, an
absent `text-halo-width` becomes 1 while an existing 1.4 survives, a null or
malformed group leaves that group alone without disturbing the others, the
default colors leave a style alone, the input object is not mutated, and the
store round trip and its fallbacks behave like the other four modules.

The Playwright stub style carries one labelled layer per group. Its existing
`place-label` and `poi-label` layers gain a `source-layer` of `place` and `poi`
and a `text-color`; a `street-label` on `transportation_name` and a
`water-label` on `water_name` join them, plus a `street-shield` on
`transportation_name` with no `text-color`. One of the four gets its color as
`hsl(...)` so the seeding conversion is exercised, and one omits
`text-halo-width` so the absent-width clause is. As with the existing stub
layers they carry no `text-field`, so no glyphs are fetched.

Playwright covers:

- setting the Streets color changes that layer's `text-color` and
  `text-halo-color` in `map.getStyle()` and issues no style request
- setting a color leaves the other three groups' layers alone
- the shield layer is untouched by a Streets color
- an unset swatch shows the style's own color for that group, including the
  layer whose color is `hsl(...)`
- an unset swatch re-seeds when the style is switched
- clearing a group with `×` restores the style's own color
- the `×` is disabled while its group is unset
- colors survive a reload
- switching style keeps the current colors applied

## Docs

`user-manual.md` gains the pickers beside the steppers and the `mapper.colors`
key, including that a group absent from a style shows a picker that does
nothing. `architecture.md` records that two transforms now compose over the
held style, and why colors live in their own key with per-group fallback rather
than joining `mapper.tweaks`.

## Left out

Icon colors. `icon-color` is independent of `text-color`, and a control for it
is a different feature with a different set of groups.

Halo width and blur. The styles' own widths carry meaning and the contrast rule
needs no tuning.

Per-style memory of colors, which stays in the backlog alongside the same note
for the steppers.
