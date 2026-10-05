# User manual

## Launching

```bash
./mapper      # or: npm start
```

The launcher builds `dist/index.html` if it is missing, starts the page server
on `127.0.0.1:8737`, and opens a chromeless Chromium window on it. Closing the
window stops the server. Set `MAPPER_PORT` to use another port; if the port is
taken, the launcher exits with an error and opens no window. Only one instance
runs at a time (see [install.md](install.md#port)).

## Using mapper from apps.rkroll.com

mapper is also served at `https://apps.rkroll.com/mapper/`, in any browser and
from any network. Open it with the shared link, which carries an access token:

```
https://apps.rkroll.com/mapper/?token=<32 hex digits>
```

Without a valid token the server refuses the page. Keep the `?token=` part when
bookmarking. mapper sends the same token with every routing request, so
routing works there too.

The web copy keeps its own places and settings, separate from the desktop
app's, because the browser stores them per address. Use
[Export and import](#export-and-import) to move them between the two.

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
not load leaves the map as it is and shows "Could not load the `<Name>` style."
at the bottom of the window. The centre, zoom, bearing, saved places, the
current route and a half-typed pin all survive a switch.

Below the style buttons, two steppers adjust how the chosen style draws. The
`−` button greys out at the bottom of each range, and `+` greys out only on
Buildings, at Off.

- **Text** scales every label in the style, from 100% up in ten-point steps,
  with no upper limit. It also scales the saved-place markers and their
  labels, so they stay legible alongside the map labels.
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
black halo, whichever contrasts. The map follows the picker while its dialog
is open; the color is saved when the dialog closes. The `×` beside a picker
puts the group back to the colors the style ships; it is greyed out while the
group is unset, and an unset picker shows the color the current style gives
that group.

Not every style draws every group. Dark and Fiord carry no points of interest,
and only Liberty, Bright and Positron name airports. A picker for a group the
current style does not draw still works and is still remembered; it just
changes nothing on screen until you switch to a style that draws it.

The four colors apply to whichever style is showing and are saved to
`localStorage` under `mapper.colors`. A missing or unrecognised color leaves
that group on the style's own colors without disturbing the other three.

Text, Buildings and the four colors are one setting shared by all five styles,
not remembered per style.

Below the colors, **Pin labels** sets how saved-place markers and their names
look:

- **Icon** scales the marker icons, from 50% up, and **Label** scales the name
  labels, from 100% up. Both move in ten-point steps with no upper limit, and
  each multiplies with Text: Text at 120% and Icon at 150% draws icons at
  180%. Each icon keeps its point on the coordinate at any size.
- **Text** sets the label color. The `×` puts it back to white.
- **Background** sets the color behind the label. A picked color draws solid;
  the `×` puts back the default translucent dark gray.
- **No background** removes the background, leaving the name on the map with
  a thin black or white outline, whichever contrasts with the text color.
  Picking a background color or clicking it again turns it off.

The pickers update the labels as the dialog moves. The pin label settings are
saved to `localStorage` under `mapper.pins`; a missing or unrecognised value
falls back on its own field without disturbing the others.

At the very bottom, **Saved data** holds **Export** and **Import…**; see
[Export and import](#export-and-import).

## Saved places

Right-click the map to drop a pin and open a name field. Press Enter to
save it, Escape to discard the pin without saving. An empty name saves as
`Unnamed`. A place remembers its position and the zoom and bearing at the
moment the pin was dropped.

Saved places appear in the panel at the top-left. Each row has, left to right:
a `⠿` drag handle, a route checkbox, the place's position in the route when
checked, its map icon, the name, an eye toggle, and a `×` delete button.

The eye hides the place's marker and label from the map; it turns red and
struck through while the place is hidden, and clicking it again brings the
marker back. A hidden place keeps its row, clicking its name still flies the
map to it, and if it is checked it is still a route waypoint. The choice is
saved with the place.

Each place also gets a marker on the map at the exact coordinate, with its
name in a label beside it. A new place gets the same blue pin used for the
right-click pending marker. Clicking the icon in a place's row opens a menu
under the row with the icons to choose from:

| Icon | Marker | Sits on the coordinate by |
|---|---|---|
| 📍 Pin | the blue pin | the pin's tip |
| ⭐ Star | a star | its center |
| 🏁 Finish flag | a chequered flag | the foot of its pole |

Picking one replaces the marker straight away; Escape or a click elsewhere
closes the menu without a change. The icon is saved with the place. Icons
scale with Text and the pin Icon stepper; the pin label colors apply to the
name label only. Clicking a place's name in the panel, or its pin, flies the map
back to its saved center, zoom, and bearing. Dragging the pin moves the
place: dropping it updates the stored position and, if the place is part of
the current route, redraws the route through the new point. The `×` button
deletes the place and removes its marker. The list is stored in
`localStorage` under `mapper.places`; an invalid entry is dropped on load
without affecting the others.

The panel header (`▾ Places (N)`) is a toggle: click it to collapse or
expand the list. Drag a row by its handle to reorder the list. Dropping on a
row inserts before it; dropping past the last row moves it to the end. The new
order is saved immediately and survives a reload.

## Walking routes

Checking two or more places draws a walking route through them **in list
order**, the same order the rows appear in the panel; each checked row shows
its position (1, 2, 3, …) in that order. Dragging a row to a new position
reorders the route along with the list. The route redraws automatically as
the selection or the list changes; a 300ms pause after the last change keeps
a run of clicks or a drag to one request.

The route is drawn as a line of round blue dots, evenly spaced along the
path. Below the panel, the distance (metres under 1 km, then kilometres to one
decimal) and walking time (whole minutes, at least 1) show with a
**Clear route** button.

Between the summary and **Clear route**, two buttons pick how the route is
chosen. **Direct** asks the routing service for the shortest walk, main roads
included. **Quiet** asks for its recommended walk, which favors side streets
and footpaths over busier roads and can be noticeably longer. Clicking either
redraws the current route. The choice is saved to `localStorage` under
`mapper.routePref`; a missing or unrecognised value falls back to Direct.

Unchecking down to fewer than two places or clicking **Clear route** clears
the route. Deleting a checked place re-routes through whatever remains
checked, and clears only if fewer than two are left.

Routing is walking only and covers the Schenectady, New York area only. It
uses a self-hosted routing service. The desktop app reaches it only from the
home network; the copy at `apps.rkroll.com` reaches it from anywhere.

| Condition | Message |
|---|---|
| Service unreachable, or any error but 404 | Could not reach the routing service. |
| Service returns 404 (points outside its area) | No walking route there; routing only covers the Schenectady area. |

The checkboxes are remembered: they are saved to `localStorage` under
`mapper.routeSelected` on every change, and a reload checks the same places
and fetches the route again. The route itself is not saved. A saved id whose
place no longer exists is dropped on load, and an unreadable value loads as
nothing checked.

Messages at the bottom of the window disappear after 4 seconds.

## Export and import

Everything mapper saves lives in the browser's `localStorage` for the address
it was opened from, so the desktop launcher (`http://127.0.0.1:8737`) and a
copy served from a website each keep their own places and settings. Export
and import move them between the two, and an exported file doubles as a
backup. Both buttons sit under **Saved data** at the bottom of the top-right
controls.

**Export** downloads `mapper-YYYY-MM-DD.json`, named for the local date. It
holds every saved key that is currently set: the view, map style, Text and
Buildings, label colors, pin labels, places, route preference and route
selection. A stored value that would load as its default is left out.

**Import…** opens a file picker. mapper then:

1. Rejects the whole file, with a message at the bottom of the window, if it
   is not valid JSON, not a mapper export, or from an export version this
   mapper does not read.
2. Checks each saved key in the file the same way mapper checks it on load. A
   key is skipped if mapper would discard its whole value on load and use the
   default instead. Inside a key that passes, a bad label color or pin label
   field falls back on its own and a bad place is dropped, as on load. Keys
   mapper does not know are ignored.
3. Asks for confirmation, naming the keys it will replace and any it skipped.
4. Replaces each of those keys and reloads the page. Keys the file does not
   carry are left as they were.

After the reload, a message names what was imported and what was skipped.
Cancelling the confirmation changes nothing.

An export looks like this:

```json
{
  "app": "mapper",
  "version": 1,
  "exported": "2026-10-05T14:03:11.402Z",
  "data": {
    "mapper.style": "dark",
    "mapper.places": [
      { "id": "pmg1x0a3f9k2", "name": "Home", "lat": 42.81, "lon": -73.94,
        "zoom": 15, "bearing": 0, "icon": "pin", "hidden": false }
    ]
  }
}
```

## When the map cannot draw

If the browser cannot create a WebGL context, the map area shows "This window
cannot draw the map: WebGL is unavailable." instead of a map.

If the map style fails to load at startup, or does not answer within 15
seconds, the map area shows "This window cannot draw the map: the map style
failed to load." A single failed tile during panning or zooming does not
trigger this; the map keeps working. A style that fails to fetch when picked
from the style buttons shows the short message described under
[Map style](#map-style) instead.
