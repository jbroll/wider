# TkX

X11 extensions for Tcl/Tk providing window management, screen capture, transparency, and shape manipulation.

## Requirements

- Tcl 9.0+, Tk
- critcl 3.2+
- X11 libraries: libX11, libXext, libXrender

## Building

```
make
```

The package is built to `lib/TkX/`.

## Usage

```tcl
lappend auto_path [file join [pwd] lib]
package require TkX
```

## API Reference

### Capture

- `TkX::capture photo window x y width height` - Capture screen/window region to Tk photo image. Use `root` for window to capture the root window.

### Shape (X11 Shape Extension)

- `TkX::input_hole window x y width height` - Create click-through region (input passes through)
- `TkX::input_reset window` - Reset input shape to normal
- `TkX::bounding_hole window x y width height` - Create visual transparency hole
- `TkX::bounding_reset window` - Reset bounding shape to normal
- `TkX::shape_watch window callback` - Register callback for ShapeNotify events

### Client-Side Decorations

- `TkX::nodecor window` - Remove window decorations (MOTIF hints)
- `TkX::move window` - Initiate WM-controlled window move
- `TkX::resize window direction` - Initiate WM-controlled resize (direction: n s e w nw ne sw se)
- `TkX::frame_offset window` - Get {x y} offset from Tk window to WM frame
- `TkX::grab_focus window` - Set keyboard focus for overrideredirect windows

### RGBA / Transparency

- `TkX::rgba_available` - Check if 32-bit ARGB visual is available
- `TkX::rgba_overlay window` - Create ARGB overlay for Tk window
- `TkX::rgba_child window x y width height` - Create ARGB child window
- `TkX::rgba_window x y width height` - Create standalone ARGB window
- `TkX::rgba_fill window_id x y width height r g b a` - Fill rectangle with RGBA color
- `TkX::rgba_clear window x y width height` - Clear region to transparent
- `TkX::set_transparent_bg window` - Set window background to transparent

### Window Management

- `TkX::active_window` - Get currently focused window ID (hex string)
- `TkX::list_windows` - List all windows with {id x y w h}
- `TkX::get_props window_id` - Get window properties (class, role, pid, cmdline, desktop)
- `TkX::move_window window_id x y w h` - Move/resize window (use -1 to skip resize)
- `TkX::set_desktop window_id desktop` - Move window to desktop
- `TkX::window_state window_id action prop1 prop2` - Change window state (action: add/remove/toggle)
- `TkX::set_property window_id property value` - Set X11 property (WM_WINDOW_ROLE, WM_COMMAND, etc.)
- `TkX::pointer_state` - Get pointer button state (for drag detection)

### Low-level Window Operations

- `TkX::window_geometry window_id x y width height` - Move/resize by window ID
- `TkX::window_destroy window_id` - Destroy window
- `TkX::window_map window_id` - Map (show) window
- `TkX::window_offset window_id` - Get window offset from parent
- `TkX::reparent child_id parent_id x y` - Reparent window
- `TkX::activate_id window_id` - Activate (focus) window by ID
- `TkX::move_id window_id` - Initiate WM move by window ID
- `TkX::resize_id window_id direction` - Initiate WM resize by window ID

## Source Files

- `TkX.tcl` - Critcl package definition
- `TkX.h` - Common types and declarations
- `TkX_core.c` - Helper functions
- `TkX_capture.c` - Screen capture
- `TkX_shape.c` - X11 Shape extension
- `TkX_csd.c` - Client-side decorations
- `TkX_rgba.c` - ARGB/transparency support
- `TkX_window.c` - Window management
- `TkX_query.c` - Window listing and properties
