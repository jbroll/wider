# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Wider is a Tcl/Tk window arranger for X11 Linux desktops. It manages window positions using named "slots" with WM_WINDOW_ROLE identity, enabling reliable multi-window layouts and position swapping. The project also includes TkX, a C extension for X11 features not available in standard Tk, and shooter, a screenshot capture tool.

## Building and Running

```bash
# Build TkX extension (requires critcl)
make

# Run GUI with slot monitoring (default)
tclsh wider.tcl

# CLI options
tclsh wider.tcl --arrange    # Snap windows to slot positions
tclsh wider.tcl --launch     # Launch missing apps from slots
tclsh wider.tcl --generate   # Generate slots.tcl from layout.tcl
tclsh wider.tcl --autostart  # Generate ~/.config/autostart/*.desktop files
tclsh wider.tcl --save       # Save window snapshot (legacy)
tclsh wider.tcl --restore    # Restore from snapshot (legacy)

# Screenshot capture tool (requires 32-bit visual)
./shooter

# Run tests
tclsh test_units.tcl         # Unit tests (pure functions)
tclsh test_roundtrip.tcl     # Integration test (window positioning)
tclsh test_shape.tcl
```

## Slot System

Slots define named window positions in `~/.config/wider/slots.tcl`:

```tcl
slot terminal-left {
    role     terminal-left
    class    Xfce4-terminal
    geometry 960x1080+0+0
    command  {xfce4-terminal --role=terminal-left}
}
```

- **role**: WM_WINDOW_ROLE for identity matching
- **class**: Fallback WM_CLASS for singleton apps
- **geometry**: X11 geometry string (WxH+X+Y)
- **command**: Launch command (apps without --role support get role set via xprop)

Windows with the same role but different slot positions are **swappable** - drag one near another's slot to swap them.

## Architecture

### Core Components

- **wider.tcl**: Slot editor GUI with window list and monitoring

  **Window List:**
  - Checkbox column to toggle managed/unmanaged state
  - Editable role, geometry, and command (double-click to edit)
  - Focus highlighting (blue) follows active window
  - All edits auto-save slots.tcl and regenerate autostart files

  **Buttons:**
  - **Refresh**: Reload window list from X11, updating positions and properties
  - **Snap**: Save current window positions to their slot configs (opposite of Arrange)
  - **Arrange**: Move windows to their slot positions. Windows already within 50px of their slot are snapped to exact position first, then remaining windows fill remaining slots. One window per slot, no duplicates.
  - **Launch**: Start apps for slots that have a `command` but no matching window
  - **Monitor**: Toggle position monitoring ON/OFF

  **Monitor Mode (when ON):**
  - Polls window positions every 500ms via `assign_and_snap_slots`
  - Windows within 150px of a matching slot snap into position
  - The active window (being dragged) is not moved
  - **Swap detection**: If two windows with the same role are near the same slot, they swap positions

- **wmctrl.tcl**: Core library in the `wm::` namespace:

  **Window Management:**
  - `wm::windows` - Lists windows with id, desktop, pid, position, size, class, cmdline, role
  - `wm::move id ?desktop? x y ?w h?` - Moves/resizes with offset compensation
  - `wm::state id add|remove|toggle prop...` - Changes window state
  - `wm::xprop id ?prop? ?value?` - Gets/sets X11 properties
  - `wm::get_role id` / `wm::set_role id role` - WM_WINDOW_ROLE access
  - `wm::parse_geometry geom` - Parse X11 geometry string

  **Slot Management:**
  - `wm::load_slots` / `wm::save_slots` - Load/save slot configuration
  - `wm::find_window_for_slot slot` - Find window by role (or class fallback)
  - `wm::find_slot_for_window id` - Find slot for window
  - `wm::arrange_slot slot` / `wm::arrange_all` - Move windows to slot positions
  - `wm::swap_slots slot1 slot2` - Swap windows between slots
  - `wm::launch_slot slot` / `wm::launch_all` - Launch missing apps
  - `wm::generate_slots` - Generate slots.tcl from layout.tcl
  - `wm::generate_autostart` - Generate ~/.config/autostart/wider-*.desktop files

  **Legacy (snapshot-based):**
  - `wm::save` / `wm::restore` - Save/restore by class+size matching

- **TkX.tcl**: Critcl-based X11 extension package providing:
  - `TkX::capture` - Capture window/screen region to Tk photo image
  - `TkX::input_hole/reset` - X11 Shape extension for click-through regions
  - `TkX::bounding_hole/reset` - Visual transparency holes
  - `TkX::shape_watch` - ShapeNotify event callbacks
  - `TkX::nodecor` - Remove window decorations
  - `TkX::move/resize` - WM-controlled window operations via _NET_WM_MOVERESIZE
  - `TkX::frame_offset` - Get offset from Tk window to WM frame
  - `TkX::rgba_*` - 32-bit ARGB visual support (overlay windows, transparency)
  - `TkX::grab_focus` - Keyboard focus for overrideredirect windows

- **shooter.tcl**: Screenshot capture tool with transparent frame UI. Uses TkX for click-through transparency and screen capture. Requires 32-bit visual (use `./shooter` wrapper).

### Window Type Detection

The `get_window_type` proc handles three window decoration types that require different coordinate offsets:
- **gtk**: Parent is root window - coordinates need halving (HiDPI scaling)
- **csd**: Client-side decorations (has _MOTIF_WM_HINTS) - use relative offset
- **ssd**: Server-side decorations - add frame extents to offset

### External Dependencies

- `wmctrl` - Window manager control CLI
- `xprop` - X11 property utility
- `xwininfo` - X11 window info utility
- `critcl` - For building TkX extension
- Tcl 9.0+, Tk
- X11 libraries: libX11, libXext, libXrender
