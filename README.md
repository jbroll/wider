# wider

X11 window management tools for Tcl/Tk, plus a desktop OpenStreetMap window,
for people who want a fixed multi-window layout on an X11 desktop that puts
every window back in its place.

```bash
wider/wider.tcl --arrange    # move every window to its slot
```

## Install

```bash
make
```

## Components

- **[wider/](wider/)** - Window arranger using named slots with WM_WINDOW_ROLE identity
- **[shooter/](shooter/)** - Screenshot capture tool with transparent overlay UI
- **[tkx/](tkx/)** - X11 extensions for Tcl/Tk (window management, capture, transparency, shapes)
- **[mapper/](mapper/)** - Chromeless OpenStreetMap window with saved places, style controls, and walking routes. Node, with its own [docs](mapper/docs/).

## Docs

- [Install](docs/install.md)
- [Development](docs/development.md)
