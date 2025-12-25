# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Wider is a Tcl/Tk window layout save/restore utility for X11 Linux desktops. It allows users to save the positions of all open windows and restore them later.

## Running the Application

```bash
# Run the main GUI application
tclsh wider.tcl
# or
wish wider.tcl

# Run position roundtrip test
tclsh test_roundtrip.tcl
```

## Architecture

### Core Components

- **wider.tcl**: Main GUI application using Tk. Provides Save/Restore buttons and enforces single-instance via a socket on port 47824.

- **wmctrl.tcl**: Core library in the `wm::` namespace providing window management functions:
  - `wm::windows` - Lists all windows with id, desktop, pid, position, size, class, and cmdline
  - `wm::move id ?desktop? x y ?w h?` - Moves/resizes windows with automatic offset compensation
  - `wm::state id add|remove|toggle prop...` - Changes window state (maximized, fullscreen, etc.)
  - `wm::xprop id ?prop? ?value?` - Gets/sets X11 window properties
  - `wm::save ?filename?` - Saves layout to `~/.config/wider/layout.tcl`
  - `wm::restore ?filename?` - Restores layout by matching windows by class and closest size

### Window Type Detection

The `get_window_type` proc handles three window decoration types that require different coordinate offsets:
- **gtk**: Parent is root window - coordinates need halving (HiDPI scaling)
- **csd**: Client-side decorations (has _MOTIF_WM_HINTS) - use relative offset
- **ssd**: Server-side decorations - add frame extents to offset

### External Dependencies

- `wmctrl` - Window manager control CLI
- `xprop` - X11 property utility
- `xwininfo` - X11 window info utility
- Tk (`package require Tk`)
