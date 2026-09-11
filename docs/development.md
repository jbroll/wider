# Development

Covers wider, shooter and TkX. mapper has its own
[development.md](../mapper/docs/development.md).

## Layout

```
Makefile          builds tkx/
wider/            window arranger (Tcl/Tk)
  wider.tcl       entry point and command-line dispatch
  windows.tcl     win:: namespace, X11 operations over TkX
  slots.tcl       slot:: namespace, slot file, arrangement, autostart
  winlist.tcl     window list
  monitor.tcl     position polling, snapping, swaps
  ui.tcl          window and layout setup
shooter/          screenshot tool; shooter is the wish wrapper
tkx/              TkX critcl extension (C), built into tkx/lib/TkX/
mapper/           Node sub-project, separate docs
```

`windows.tcl` and `slots.tcl` open with an API listing for their namespace;
keep those headers current with the code.

## Build

```bash
make          # critcl -force -pkg -libdir lib TkX.tcl, run in tkx/
make clean
```

## Test

```bash
tclsh wider/test_units.tcl       # unit tests for windows.tcl and slots.tcl
tclsh wider/test_roundtrip.tcl   # saves the live layout to /tmp/test_layout.tcl and checks window positions round-trip
tclsh tkx/test_shape.tcl         # opens a Tk window to exercise the shape extension; q or Escape quits
```

All three need TkX built. `test_roundtrip.tcl` and `test_shape.tcl` need a
running X11 session, and the round-trip test moves real windows.

No linter is configured.

## Release

None. Everything runs from the checkout.
