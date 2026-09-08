# Install

## Requirements

- Node 22+
- `chromium` on `PATH`
- X11

## Install

```bash
npm install
```

from `mapper/`. `npm run build` (or the first run of `./mapper`) bundles
`src/` into `dist/index.html`.

## Desktop menu and autostart

`mapper.desktop` has an `Exec` line pointing at the `mapper` launcher in
this checkout; edit it if you clone elsewhere. Copy it to
`~/.local/share/applications/` to add Mapper to the desktop menu, or to
`~/.config/autostart/` to start it at login.

## Chromium profile

`~/.config/mapper/chrome` holds the private Chromium profile the launcher
passes as `--user-data-dir`. Deleting it resets the window, including the
`localStorage` that holds the saved view and places.

## Port

`serve.js` listens on `127.0.0.1:8737` by default, so the saved view and
places persist across launches. Set `MAPPER_PORT` to use a different port.
If the port is already in use, the launcher stops with an error instead of
opening a window.
