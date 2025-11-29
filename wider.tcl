#!/usr/bin/env wish
# wider.tcl - Window layout save/restore utility

package require Tk

source [file join [file dirname [info script]] wmctrl.tcl]

# Main window setup
wm title . "Wider"
wm resizable . 0 0
tk appname wider

# Status variable
set status "Ready"

# Save button
proc do_save {} {
    global status
    try {
        set count [wm::save]
        set status "Saved $count windows"
    } on error {msg} {
        set status "Error: $msg"
    }
}

# Restore button
proc do_restore {} {
    global status
    try {
        set count [wm::restore]
        set status "Restored $count windows"
    } on error {msg} {
        set status "Error: $msg"
    }
}

# UI
ttk::frame .f -padding 10
ttk::button .f.save -text "Save" -command do_save -width 10
ttk::button .f.restore -text "Restore" -command do_restore -width 10
ttk::label .f.status -textvariable status -foreground gray

grid .f -sticky nsew
grid .f.save .f.restore -padx 5 -pady 5
grid .f.status -columnspan 2 -pady {5 0}

# Keep window on top
wm attributes . -topmost 1
