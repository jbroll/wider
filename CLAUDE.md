# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Wider is a Tcl/Tk window arranger for X11 Linux desktops. It manages window positions using named "slots" with WM_WINDOW_ROLE identity, enabling reliable multi-window layouts and position swapping. The project also includes TkX, a C extension for X11 features not available in standard Tk, shooter, a screenshot capture tool, and mapper, a chromeless OpenStreetMap window.

## Building and Running

```bash
# Build TkX extension (requires critcl)
make

# Run GUI with slot monitoring (default)
tclsh wider/wider.tcl

# CLI options
tclsh wider/wider.tcl --arrange    # Snap windows to slot positions
tclsh wider/wider.tcl --launch     # Launch missing apps from slots
tclsh wider/wider.tcl --generate   # Generate slots.tcl from layout.tcl
tclsh wider/wider.tcl --autostart  # Generate ~/.config/autostart/*.desktop files
tclsh wider/wider.tcl --save       # Save the current layout
tclsh wider/wider.tcl --restore    # Restore the saved layout

# Screenshot capture tool (requires 32-bit visual)
shooter/shooter

# Run tests
tclsh wider/test_units.tcl         # Unit tests (pure functions)
tclsh wider/test_roundtrip.tcl     # Integration test (window positioning)
tclsh tkx/test_shape.tcl           # TkX shape extension test
```

## wider, TkX and shooter

Slot format, GUI buttons, monitor mode and autostart are documented in
[wider/README.md](wider/README.md). The TkX C extension's full API is in
[tkx/README.md](tkx/README.md). The `win::` and `slot::` APIs are listed in
header comments at the top of `wider/windows.tcl` and `wider/slots.tcl`; those
headers are the reference, so update them with the code.

Quirks that bite:

- A slot is keyed by role, not by name, and one role holds a list of positions:
  `role -> {class C command CMD positions {{x X y Y w W h H} ...}}`.
  Two windows sharing a role is the normal case, and it is what makes them
  swappable.
- `wider/wmctrl.tcl` and the `wm::` namespace are gone. The code is split into
  `windows.tcl` (`win::`, X11 operations over TkX), `slots.tcl` (`slot::`,
  configuration and arrangement), `winlist.tcl`, `monitor.tcl` and `ui.tcl`.
- Nothing in `wider/` or `shooter/` runs until `make` builds TkX into
  `tkx/lib/TkX/`. A missing build surfaces as a `package require TkX` failure.
- shooter needs a 32-bit visual and must be started through the `shooter/shooter`
  wrapper, which passes `-visual "truecolor 32"` to wish.

## mapper

A Node/Preact/MapLibre subproject in an otherwise Tcl repository, with its own
doc set: [user manual](mapper/docs/user-manual.md) for the feature set,
[architecture](mapper/docs/architecture.md) for why it is built this way,
[development](mapper/docs/development.md) for build and test,
[backlog](mapper/docs/backlog.md) for open defects.

Quirks that bite:

- The app serves one built file. Editing `mapper/src/` changes nothing at
  runtime until `npm run build` rewrites `dist/index.html`.
- Never add a route, marker or overlay with `map.addSource`/`map.addLayer`.
  `map.setStyle` runs on every style switch, stepper move and color commit, and
  destroys anything added outside the style body. New map content goes in the
  pure transform chain in `src/styles.jsx` instead.
- A new Playwright spec must be added to `testMatch` in
  `playwright.config.js` or it silently never runs.
- The routing specs stub the OpenRouteService address hardcoded in
  `src/route.js` with `page.route`, and `test/pw.js` aborts every other
  non-loopback request, so tests never reach a real network service.
- Port 8737 is fixed on purpose: `localStorage` is origin-keyed, and every
  saved setting depends on the origin being stable across launches. Only one
  instance runs at a time.

## External Dependencies

- `critcl` - For building TkX extension
- `xrandr` - Monitor enumeration (shooter only)
- Tcl 9.0+, Tk
- X11 libraries: libX11, libXext, libXrender
- Node 22+ and `chromium` (mapper only)
