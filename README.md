# wider

X11 window management tools for Tcl/Tk.

## Components

- **[wider/](wider/)** - Window arranger using named slots with WM_WINDOW_ROLE identity
- **[shooter/](shooter/)** - Screenshot capture tool with transparent overlay UI
- **[tkx/](tkx/)** - X11 extensions for Tcl/Tk (window management, capture, transparency, shapes)

## Requirements

- Tcl 9.0+, Tk
- critcl 3.2+ (for building TkX)
- X11 libraries: libX11, libXext, libXrender

## Building

```
make
```

This builds the TkX extension required by wider and shooter.

## Quick Start

```bash
# Window arranger GUI
wider/wider.tcl

# Screenshot capture
shooter/shooter
```

See individual component READMEs for detailed usage.
