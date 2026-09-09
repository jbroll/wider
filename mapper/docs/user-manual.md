# User manual

## Navigation

- **Pan**: left-drag.
- **Zoom**: mouse wheel.
- **Rotate and tilt**: right-drag, or ctrl-drag.
- **Return to north**: click the compass button in the top-right controls.
  It resets bearing to 0 and pitch to 0.

## View persistence

The map view (center, zoom, bearing, pitch) is saved to `localStorage`
under `mapper.view` on `moveend`, 300ms after movement stops. On load, a
missing or invalid stored value falls back to the default view: zoom 3.5
over the continental US, bearing 0, pitch 0.

## Map style

The button group below the navigation controls at the top right picks the
map style: Liberty, Bright, Positron, Dark, or Fiord. The current one is
marked. The choice is saved to `localStorage` under `mapper.style` and is
restored on the next launch; a missing or unrecognised value falls back to
Liberty.

Switching fetches the new style before applying it, so a style that will
not load leaves the map as it is and shows a short-lived message at the
bottom of the window instead. The centre, zoom, bearing, saved places and a
half-typed pin all survive a switch.

Below the style buttons, two steppers adjust how the chosen style draws:

- **Text** scales every label in the style, from 100% to 200% in ten-point
  steps. It also scales the saved-place markers, so they stay legible
  alongside the labels.
- **Buildings** sets the zoom below which buildings are not drawn: 13, 14, 15,
  16, or Off. Buildings only exist in the tiles from zoom 13, so 13 is the
  default and draws them as early as the data allows. Off removes the
  building layers from the style outright; the tiles carry no building data
  past zoom 14, so raising the floor further would only mask that data
  instead of removing it.

Both settings apply to whichever style is showing and are saved to
`localStorage` under `mapper.tweaks`. A missing or unrecognised value falls
back to 100% text and buildings from zoom 13.

Below the steppers, four color pickers set the label colors:

- **Places** covers town, city and country names.
- **Streets** covers street and road names.
- **POIs** covers points of interest and airport names.
- **Water** covers lake, sea and river names.

Picking a color recolors every label in that group and gives it a white or
black halo, whichever contrasts. The `×` beside a picker puts the group back to
the colors the style ships; it is greyed out while the group is unset, and an
unset picker shows the color the current style gives that group.

Not every style draws every group. Dark and Fiord carry no points of interest,
and only Liberty, Bright and Positron name airports. A picker for a group the
current style does not draw still works and is still remembered; it just
changes nothing on screen until you switch to a style that draws it.

The four colors apply to whichever style is showing and are saved to
`localStorage` under `mapper.colors`. A missing or unrecognised color leaves
that group on the style's own colors without disturbing the other three.

## Saved places

Right-click the map to drop a pin and open a name field. Press Enter to
save it, Escape to discard the pin without saving.

Saved places appear in the panel at the top-left, and each also gets a
marker on the map showing its name. Clicking a place's name in the panel,
or its marker, flies the map back to its saved center, zoom, and bearing.
The `×` button next to a place deletes it and removes its marker. The list
is stored in `localStorage` under `mapper.places`.

The panel header (`Places (N)`) is a toggle: click it to collapse or
expand the list.

## Walking routes

Each saved place has a checkbox in the panel list. Checking two or more draws
a walking route through them **in the order they were checked**, not list
order; each checked row shows its position (1, 2, 3, …). The route redraws
automatically as the selection changes - there is no button to press - and a
short pause after the last click keeps a run of clicks from firing a request
per click.

Routing is walking only and covers the Schenectady, New York area only; it
needs a self-hosted routing service on the local network, so it does not work
away from that network. Once a route is drawn, its distance and duration show
below the panel, with a button to clear it. Unchecking down to fewer than two
places, deleting a checked place, or clicking Clear also clears the route -
deleting a checked place re-routes through whatever remains checked rather
than clearing outright, as long as two or more are still checked.

If the routing service cannot be reached, a message says so. If the two
points are outside the routable area, a different message says that instead.

The route is not saved - a reload starts with nothing checked and no route
drawn.

## No WebGL

If the browser cannot create a WebGL context, the map area shows one line
of text, "This window cannot draw the map: WebGL is unavailable," instead
of a map.

If the map style itself fails to load, the map area instead shows "This
window cannot draw the map: the map style failed to load." A single failed
tile during panning or zooming does not trigger this; the map keeps working,
and neither does a style that fails when switched from the style buttons.
