# Install

## Requirements

- Node 22+ (`engines` in `package.json`)
- `chromium` on `PATH`
- X11

npm dependencies: `maplibre-gl` ^5.0.0, `preact` ^10.29.8, `@preact/signals`
^1.3.4, `esbuild` ^0.24.0, and `@playwright/test` ^1.49.0 for the browser
tests.

Network services, both outside this project:

- Map styles and vector tiles from `https://tiles.openfreemap.org/styles/<id>`.
  No API key.
- Walking routes from a self-hosted OpenRouteService, which `serve.js` reaches
  at `http://192.168.1.169:8082/ors`. Without it everything but routing works.

## Install

```bash
npm install
npm run build
```

from `mapper/`. `npm run build` bundles `src/` into `dist/index.html`. The
first run of `./mapper` does the same if `dist/index.html` is missing.

## Upgrade

```bash
git pull
npm install
npm run build
```

The launcher builds only when `dist/index.html` is missing, so after a pull it
keeps serving the old build until `npm run build` runs.

## Routing service

The page sends routing requests to `ors/` relative to its own address, and
`serve.js` proxies `/ors/` to `http://192.168.1.169:8082/ors`. To use a
different server, set `MAPPER_ORS_URL` to its `http://` base URL, ending in
`/ors`, before running `./mapper`. No rebuild is needed. The `foot-walking`
profile is the `PROFILE` constant in `src/route.js`.

## Deploying to apps.rkroll.com

`deploy.conf` deploys mapper with
[deploy.sh](https://github.com/jbroll/deploy.sh) as a path mount on the
`apps.rkroll.com` vhost. The vhost is the root project, deployed from
`~/src/rkroll.com/apps`. It must have been deployed by a deploy.sh that
includes mounted apps in the vhost; mapper's configure stage warns when it
was not.

```bash
npm install                            # the build stage runs npm run build here
../../deploy.sh/deploy.sh init .       # first deploy
../../deploy.sh/deploy.sh update .     # later: rebuild and resync
```

from `mapper/`, with deploy.sh checked out beside this repo. `deploy.conf`
uses `APACHE_MOUNT_PATH` and `APACHE_PROXY_URLS`, which exist only on
deploy.sh's `apache-mount-path` branch until it merges.

What the deploy sets up:

- `dist/index.html` synced to `/var/www/mapper` and served at
  `https://apps.rkroll.com/mapper/`. Only `dist/` is copied: the apache
  module's configure stage syncs `dist/` when it exists, never the sources or
  `node_modules`.
- `/mapper/ors` proxied to `https://symon.rkroll.com:8443/routing/ors`.
- Token auth over the whole `/mapper` mount, page and proxy alike. A request
  passes with `?token=<32 hex>` in its query string, and there are no cookies,
  so the page forwards its own token on each routing request.
- No certificate of its own: `letsencrypt` is left out of `DEPLOY_TYPES`
  because the `apps.rkroll.com` vhost owns the cert.

## Desktop menu and autostart

`mapper.desktop` has an `Exec` line pointing at the `mapper` launcher in
this checkout; edit it if you clone elsewhere. Copy it to
`~/.local/share/applications/` to add Mapper to the desktop menu, or to
`~/.config/autostart/` to start it at login.

A desktop or autostart launch does not run a login shell, so it never sees
the PATH your shell profile builds, an nvm-installed node included. The
launcher checks PATH first, then falls back to the newest node under
`$NVM_DIR` (default `~/.nvm`) or `~/.config/nvm`. If node lives somewhere else
entirely, put it on PATH in the `Exec` line of `mapper.desktop`, or symlink
it into one of those nvm directories.

## Chromium profile

`~/.config/mapper/chrome` holds the private Chromium profile the launcher
passes as `--user-data-dir`. Deleting it resets the window, including the
`localStorage` that holds the saved view, style, settings and places.

## Port

`serve.js` listens on `127.0.0.1:8737` by default, so the saved settings
persist across launches: `localStorage` is keyed by origin, and a different
port is a different origin with none of them. Set `MAPPER_PORT` to use a
different port. If the port is already in use, the launcher stops with an
error instead of opening a window.

Only one instance runs at a time. If a first launch is already running on
the default port and a second launch sets `MAPPER_PORT` to a free port,
its `serve.js` starts, but Chromium's profile singleton hands the new URL
to the already-running Chromium process instead of starting a new one. The
second launcher's `chromium` command returns immediately, so its `EXIT`
trap kills the server it just started, which is the server backing the tab
the singleton just opened.
