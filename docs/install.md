# Install

Covers wider, shooter and TkX. mapper has its own
[install.md](../mapper/docs/install.md).

## Requirements

- Tcl 9.0+, Tk
- critcl 3.2+, to build TkX
- X11 libraries: libX11, libXext, libXrender
- `xrandr`, for shooter's monitor check
- For the wider GUI only: the `jbr::layout` and `jbr::func` packages from
  jbr.tcl, found through the module path `~/lib/tcl8/site-tcl`, and
  `/home/john/src/jbr.tcl/layout/layoutscroll.tcl`, which `wider.tcl` sources
  by that absolute path. The command-line options do not need them.

Some paths are hardcoded to the author's machine:

| Path | Where |
|---|---|
| `/home/john/bin/wish9.1` | `wider/wider.tcl` shebang and `shooter/shooter` |
| `../../critcl/lib` (relative to `tkx/`) | `tkx/Makefile`, passed to critcl as `TCLLIBPATH` |
| `/home/john/src/jbr.tcl/layout/layoutscroll.tcl` | `wider/wider.tcl` |

## Build

```bash
make
```

Builds TkX into `tkx/lib/TkX/`. wider and shooter find it through
`tkx/lib` relative to their own directory; nothing runs until it is built.
`make clean` removes the build.

## Configuration

| File | Written by |
|---|---|
| `~/.config/wider/slots.tcl` | the GUI's Save button, any edit in its window list, and `--generate` |
| `~/.config/wider/layout.tcl` | `wider.tcl --save` |
| `~/.config/autostart/wider-*.desktop` | `wider.tcl --autostart`, the GUI's Save button, and any edit in its window list |
| `~/.screenshot` | shooter, on exit |

The slot file format is in [wider/README.md](../wider/README.md#slots).

## Upgrade

```bash
git pull
make
```
