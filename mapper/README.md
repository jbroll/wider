# mapper

A chromeless desktop OpenStreetMap window for X11, for people who arrange
their desktop with wider and want a map that sits in a slot like any other
application. It runs as a Chromium `--app` window with `WM_CLASS` `Mapper`,
and has saved places with a choice of marker icon, five map styles, label and
marker size and color controls, address search, and walking routes between
saved places. The
same page is also served at `https://apps.rkroll.com/mapper/` behind a token
link.

```bash
./mapper
```

## Install

```bash
npm install && npm run build
```

## Docs

- [Quickstart](docs/quickstart.md)
- [Install](docs/install.md)
- [User manual](docs/user-manual.md)
- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Backlog](docs/backlog.md)
