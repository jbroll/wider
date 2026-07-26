# shooter

Screenshot capture tool with transparent overlay UI.

## Usage

```
./shooter
```

Requires 32-bit visual. The wrapper script passes `-visual "truecolor 32"` to wish.

## How it works

Uses TkX extension for:
- `TkX::capture` - Screen/window capture to Tk photo image
- `TkX::grab_focus` - Keyboard focus for overrideredirect window
- RGBA visual support for true transparency

The overlay window shows a live desktop background with a draggable/resizable capture region. Press Enter to capture, Escape to cancel.

Position and size are saved to `~/.screenshot` on exit. On startup the saved rectangle is checked against the monitors `xrandr --listmonitors` reports; if it is no longer fully visible - a monitor was detached, or the layout changed - it is resized and moved onto the monitor covering most of it, or onto the primary monitor when it covers none.
