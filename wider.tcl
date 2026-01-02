#!/usr/bin/env tclsh
# wider.tcl - Window layout save/restore utility
#
# Usage:
#   wider.tcl              - GUI mode (with slot monitoring)
#   wider.tcl --restore    - restore layout and exit
#   wider.tcl --save       - save layout and exit
#   wider.tcl --arrange    - arrange windows to slots and exit
#   wider.tcl --launch     - launch missing apps from slots and exit
#   wider.tcl --generate   - generate slots.tcl from layout.tcl

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
        --arrange - -a {
            wm::load_slots
            set count [wm::arrange_all]
            puts "Arranged $count windows"
            exit 0
        }
        --launch - -l {
            wm::load_slots
            set count [wm::launch_all]
            puts "Launched $count apps"
            exit 0
        }
        --generate - -g {
            set count [wm::generate_slots]
            puts "Generated $count slots from layout"
            exit 0
        }
        --help - -h {
            puts "Usage: wider.tcl \[option\]"
            puts "  --restore, -r   Restore window layout and exit"
            puts "  --save, -s      Save window layout and exit"
            puts "  --arrange, -a   Arrange windows to slots and exit"
            puts "  --launch, -l    Launch missing apps from slots and exit"
            puts "  --generate, -g  Generate slots.tcl from layout.tcl"
            puts "  (no args)       Run GUI with slot monitoring"
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

# Load slot configuration
wm::load_slots

# ========== Monitoring ==========

# Monitoring state
set monitoring 1
set monitor_interval 500  ;# ms
set swap_threshold 150    ;# pixels - distance to trigger swap
set window_positions {}   ;# id -> {x y} last known position

# Track window positions for managed windows
proc update_positions {} {
    global window_positions
    set window_positions {}
    foreach win [wm::windows] {
        set slot [wm::find_slot_for_window [dict get $win id]]
        if {$slot ne ""} {
            dict set window_positions [dict get $win id] [dict create \
                x [dict get $win x] y [dict get $win y] \
                w [dict get $win w] h [dict get $win h] \
                slot $slot]
        }
    }
}

# Check for window movements and trigger swaps
proc check_movements {} {
    global window_positions swap_threshold status
    variable wm::slots

    set current_wins [wm::windows]

    foreach win $current_wins {
        set id [dict get $win id]
        set slot [wm::find_slot_for_window $id]
        if {$slot eq ""} continue

        # Skip if we don't have previous position
        if {![dict exists $window_positions $id]} continue

        set prev [dict get $window_positions $id]
        set prev_slot [dict get $prev slot]

        # Check if window moved significantly
        set dx [expr {abs([dict get $win x] - [dict get $prev x])}]
        set dy [expr {abs([dict get $win y] - [dict get $prev y])}]

        if {$dx < 20 && $dy < 20} continue  ;# No significant movement

        # Window moved - check if it's near another slot
        dict for {other_slot cfg} $wm::slots {
            if {$other_slot eq $prev_slot} continue

            set dist [wm::slot_distance $win $other_slot]
            if {$dist < $swap_threshold} {
                # Trigger swap!
                set status "Swapping $prev_slot <-> $other_slot"
                wm::swap_slots $prev_slot $other_slot
                update_positions
                return
            }
        }
    }

    # Update positions for next iteration
    update_positions
}

# Monitor loop
proc monitor_loop {} {
    global monitoring monitor_interval

    if {!$monitoring} return

    catch {check_movements}
    after $monitor_interval monitor_loop
}

# Toggle monitoring
proc toggle_monitoring {} {
    global monitoring status
    set monitoring [expr {!$monitoring}]
    if {$monitoring} {
        set status "Monitoring ON"
        update_positions
        monitor_loop
    } else {
        set status "Monitoring OFF"
    }
    update_monitor_button
}

# Update monitor button appearance
proc update_monitor_button {} {
    global monitoring
    if {$monitoring} {
        .f.monitor configure -text "Monitor: ON" -style Monitor.On.TButton
    } else {
        .f.monitor configure -text "Monitor: OFF" -style Monitor.Off.TButton
    }
}

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

# Arrange button - snap all windows to slot positions
proc do_arrange {} {
    global status
    try {
        set count [wm::arrange_all]
        set status "Arranged $count windows"
        update_positions
    } on error {msg} {
        set status "Error: $msg"
    }
}

# Launch button - launch missing apps
proc do_launch {} {
    global status
    try {
        set count [wm::launch_all]
        if {$count > 0} {
            set status "Launched $count apps"
        } else {
            set status "All apps running"
        }
    } on error {msg} {
        set status "Error: $msg"
    }
}

# UI styles for monitor button
ttk::style configure Monitor.On.TButton -foreground darkgreen
ttk::style configure Monitor.Off.TButton -foreground gray

# UI
ttk::frame .f -padding 10

# Row 1: Layout management
ttk::button .f.save -text "Save" -command do_save -width 8
ttk::button .f.restore -text "Restore" -command do_restore -width 8

# Row 2: Slot management
ttk::button .f.launch -text "Launch" -command do_launch -width 8
ttk::button .f.arrange -text "Arrange" -command do_arrange -width 8

# Row 3: Monitor toggle
ttk::button .f.monitor -text "Monitor: ON" -command toggle_monitoring -width 18 -style Monitor.On.TButton

# Status
ttk::label .f.status -textvariable status -foreground gray

grid .f -sticky nsew
grid .f.save .f.restore -padx 5 -pady 2
grid .f.launch .f.arrange -padx 5 -pady 2
grid .f.monitor -columnspan 2 -pady 2
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

    # Start monitoring loop (on by default)
    after 200 {
        update_positions
        monitor_loop
    }
}
