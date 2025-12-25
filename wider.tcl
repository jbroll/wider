#!/usr/bin/env tclsh
# wider.tcl - Window layout save/restore utility
#
# Usage:
#   wider.tcl              - GUI mode
#   wider.tcl --restore    - restore layout and exit
#   wider.tcl --save       - save layout and exit

source [file join [file dirname [info script]] wmctrl.tcl]

# CLI mode - handle before loading Tk
if {[llength $argv] > 0} {
    switch -- [lindex $argv 0] {
        --restore - -r {
            set count [wm::restore]
            puts "Restored $count windows"
            exit 0
        }
        --save - -s {
            set count [wm::save]
            puts "Saved $count windows"
            exit 0
        }
        --help - -h {
            puts "Usage: wider.tcl \[--restore|--save\]"
            puts "  --restore, -r  Restore window layout and exit"
            puts "  --save, -s     Save window layout and exit"
            puts "  (no args)      Run GUI"
            exit 0
        }
        default {
            puts stderr "Unknown option: [lindex $argv 0]"
            exit 1
        }
    }
}

# GUI mode
package require Tk

# Single instance enforcement
proc check_single_instance {} {
    set port 47824  ;# Unique port for wider (talkie uses 47823)

    # Try to connect to existing instance
    if {![catch {socket localhost $port} sock]} {
        puts $sock "raise"
        flush $sock
        close $sock
        exit 0
    }

    # No existing instance - become the server
    socket -server handle_instance_request $port
}

proc handle_instance_request {sock addr port} {
    if {[gets $sock line] >= 0 && $line eq "raise"} {
        wm deiconify .
        raise .
        focus -force .
    }
    close $sock
}

check_single_instance

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

# Position in upper-right corner (to the left of talkie)
after idle {
    update idletasks
    set sw [winfo screenwidth .]
    set ww [winfo reqwidth .]
    # Position: right edge minus window width minus margin (talkie is ~731 wide at x=5031)
    # Place wider to the left of where talkie typically sits
    wm geometry . +[expr {$sw - $ww - 800}]+50

    # Set _NET_WM_PID so we can be identified for restart
    after 100 {
        set frame [wm frame .]
        if {$frame ne "0x0"} {
            exec xprop -id $frame -f _NET_WM_PID 32c -set _NET_WM_PID [pid]
        }
    }
}
