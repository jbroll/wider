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

## Saved places

Right-click the map to drop a pin and open a name field. Press Enter to
save it, Escape to discard the pin without saving.

Saved places appear in the panel at the top-left. Clicking a place's name
flies the map back to its saved center, zoom, and bearing. The `×` button
next to a place deletes it. The list is stored in `localStorage` under
`mapper.places`.

The panel header (`Places (N)`) is a toggle: click it to collapse or
expand the list.

## No WebGL

If the browser cannot create a WebGL context, the map area shows one line
of text, "This window cannot draw the map: WebGL is unavailable," instead
of a map.

If the map style itself fails to load, the map area instead shows "This
window cannot draw the map: the map style failed to load." A single failed
tile during panning or zooming does not trigger this; the map keeps working,
and neither does a style that fails when switched from the style buttons.
