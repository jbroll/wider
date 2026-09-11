# wider

Window arranger for X11. Saves and restores window positions using named slots.

## Requirements

- Tcl 9.0+, Tk
- critcl (for building TkX)
- X11 libraries: libX11, libXext, libXrender

## Building

```
make
```

## wider.tcl

Manages window layouts using slots. Windows are matched by WM_WINDOW_ROLE.

### Usage

```
wider.tcl              # GUI
wider.tcl --arrange    # Move windows to slot positions
wider.tcl --launch     # Start apps for empty slots
wider.tcl --generate   # Generate slots.tcl from layout.tcl
wider.tcl --autostart  # Generate ~/.config/autostart/*.desktop files
wider.tcl --save       # Save the current layout
wider.tcl --restore    # Restore the saved layout
```

Each long option has a single-letter form except `--autostart`; `--help` lists
them.

### Slots

Stored in `~/.config/wider/slots.tcl`, one `role` block per WM_WINDOW_ROLE:

```tcl
role terminal {
    class   Xfce4-terminal
    command {xfce4-terminal --role=terminal}
    position 960x1080+0+0
    position 960x1080+960+0
}
```

- **role name** - WM_WINDOW_ROLE that matches windows to this block
- **class** - Fallback WM_CLASS when no window carries the role
- **command** - Launch command, optional
- **position** - One `WxH+X+Y` per window; a role may have several

Windows sharing a role are interchangeable across its positions, which is
what lets two of them swap. The older `slot NAME {role … class … geometry …
command …}` format is still read and converted on load; Save writes the
`role` format.

When a role is launched, a `--geometry=` in its command is replaced with the
position's geometry; for class `Xfce4-terminal` one is appended if absent.
Autostart files also append `--role=NAME` when the command has no `--role=`.

### GUI

The window list shows all managed windows. Double-click to edit role, geometry, or command. Checkbox toggles whether a window is managed.

Buttons:

- **Refresh** - Reload window list from X11
- **Save** - Save current window positions to their slots and regenerate autostart files. Workflow: Monitor OFF → move windows → Refresh → Save → Monitor ON.
- **Arrange** - Move windows to their slot positions. Each position takes the nearest unassigned window with its role (or class), one window per position.
- **Launch** - Start apps for slots that have a command but no matching window
- **Monitor** - Toggle position monitoring on/off

### Monitor Mode

When monitoring is on (polls every 500ms):
- Windows within 150px of a matching slot snap into position
- The active window (being dragged) is not moved
- **Swap**: If two windows with the same role are near the same slot, they swap positions

### Autostart

`wider.tcl --autostart` generates `~/.config/autostart/wider-*.desktop` files for each slot with a command. These start apps with correct roles at login.

## Files

- `wider.tcl` - Entry point, CLI dispatch, single-instance check
- `windows.tcl` - `win::` namespace: X11 window operations over TkX
- `slots.tcl` - `slot::` namespace: role configuration, arrangement, autostart
- `winlist.tcl` - Window list rendering and edit handlers
- `monitor.tcl` - Position polling, snapping and swap detection
- `ui.tcl` - Window and layout setup

`windows.tcl` and `slots.tcl` each open with an API listing for their
namespace. Those headers are the reference; keep them current with the code.
