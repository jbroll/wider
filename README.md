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
wider.tcl --autostart  # Generate ~/.config/autostart/*.desktop files
```

### Slots

Stored in `~/.config/wider/slots.tcl`:

```tcl
slot terminal-left {
    role     terminal-left
    class    Xfce4-terminal
    geometry 960x1080+0+0
    command  {xfce4-terminal --role=$role --geometry=$geometry}
}
```

Fields:
- **role** - WM_WINDOW_ROLE for matching windows to slots
- **class** - Fallback WM_CLASS if role not set
- **geometry** - WxH+X+Y position and size
- **command** - Launch command for this slot

Command macros:
- `$role` - Expands to the slot's role value
- `$geometry` - Expands to WxH+X+Y geometry string

If command doesn't contain `--role=`, wider appends `--role=$role` automatically.

### GUI

The window list shows all managed windows. Double-click to edit role, geometry, or command. Checkbox toggles whether a window is managed.

Buttons:

- **Refresh** - Reload window list from X11
- **Snap** - Save current window positions to their slots. Creates new slots for windows with roles that don't have one.
- **Arrange** - Move windows to their slot positions. Windows within 50px of a slot snap first, then remaining windows fill remaining slots.
- **Launch** - Start apps for slots that have a command but no matching window
- **Monitor** - Toggle position monitoring on/off

### Monitor Mode

When monitoring is on (polls every 500ms):
- Windows within 150px of a matching slot snap into position
- The active window (being dragged) is not moved
- **Swap**: If two windows with the same role are near the same slot, they swap positions

### Autostart

`wider.tcl --autostart` generates `~/.config/autostart/wider-*.desktop` files for each slot with a command. These start apps with correct roles at login.

## shooter.tcl

Screenshot tool with adjustable capture region.

```
./shooter
```

Requires 32-bit visual. The wrapper script passes `-visual "truecolor 32"` to wish.

## Files

- `wider.tcl` - Main GUI
- `wmctrl.tcl` - Window management library (wm:: namespace)
- `tkx/` - TkX X11 extension (critcl)
- `shooter.tcl` - Screenshot capture
- `shooter` - Wrapper for 32-bit visual
