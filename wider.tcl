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
#   wider.tcl --autostart  - generate autostart .desktop files from slots

# Add TkX library path
lappend auto_path [file join [file dirname [info script]] lib]

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
        --autostart {
            wm::load_slots
            set count [wm::generate_autostart]
            puts "Generated $count autostart files in ~/.config/autostart/"
            exit 0
        }
        --help - -h {
            puts "Usage: wider.tcl \[option\]"
            puts "  --restore, -r   Restore window layout and exit"
            puts "  --save, -s      Save window layout and exit"
            puts "  --arrange, -a   Arrange windows to slots and exit"
            puts "  --launch, -l    Launch missing apps from slots and exit"
            puts "  --generate, -g  Generate slots.tcl from layout.tcl"
            puts "  --autostart     Generate autostart .desktop files from slots"
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

# Stateless slot assignment and snap
# Each cycle: assign windows to slots by proximity, snap non-active windows
# Swap detection: if window is dragged near an occupied slot, swap them
proc assign_and_snap_slots {} {
    global status swap_threshold

    # Get all windows and active window
    set windows [wm::windows]
    set active_id [TkX::active_window]

    # Build role -> slots mapping
    set slots_by_role {}
    dict for {name cfg} $wm::slots {
        if {![dict exists $cfg role]} continue
        dict lappend slots_by_role [dict get $cfg role] $name
    }

    # First pass: find windows that are exactly in their slot
    # and windows that need assignment
    set slot_occupant {}  ;# slot_name -> window_id (for windows in slot)
    set floating {}       ;# windows not in any slot: {id win_data}

    foreach win $windows {
        set role [dict get $win role]
        if {$role eq ""} continue
        if {![dict exists $slots_by_role $role]} continue

        set id [dict get $win id]
        set wx [dict get $win x]
        set wy [dict get $win y]

        # Check if window is exactly in any slot of its role
        set found_slot ""
        foreach slot_name [dict get $slots_by_role $role] {
            set cfg [dict get $wm::slots $slot_name]
            if {$wx == [dict get $cfg x] && $wy == [dict get $cfg y]} {
                set found_slot $slot_name
                break
            }
        }

        if {$found_slot ne ""} {
            dict set slot_occupant $found_slot $id
        } else {
            lappend floating [list $id $win]
        }
    }

    # Second pass: process floating windows
    # Check for swap or snap to closest slot
    foreach entry $floating {
        lassign $entry win_id win_data
        set role [dict get $win_data role]

        # Find closest slot of matching role
        set best_slot ""
        set best_dist 999999
        foreach slot_name [dict get $slots_by_role $role] {
            set dist [wm::slot_distance $win_data $slot_name]
            if {$dist < $best_dist} {
                set best_dist $dist
                set best_slot $slot_name
            }
        }

        if {$best_slot eq ""} continue

        set cfg [dict get $wm::slots $best_slot]
        set slot_x [dict get $cfg x]
        set slot_y [dict get $cfg y]
        set slot_w [dict get $cfg w]
        set slot_h [dict get $cfg h]

        # Check if this slot is occupied
        if {[dict exists $slot_occupant $best_slot]} {
            # Slot is occupied - check if we're close enough for swap
            if {$best_dist <= $swap_threshold} {
                set occupant_id [dict get $slot_occupant $best_slot]

                # Find empty slot for the displaced window
                set empty_slot ""
                foreach other_slot [dict get $slots_by_role $role] {
                    if {![dict exists $slot_occupant $other_slot]} {
                        set empty_slot $other_slot
                        break
                    }
                }

                if {$empty_slot ne ""} {
                    # Perform swap
                    set empty_cfg [dict get $wm::slots $empty_slot]

                    # Move occupant to empty slot (if not active)
                    if {$occupant_id ne $active_id} {
                        wm::move $occupant_id 0 [dict get $empty_cfg x] [dict get $empty_cfg y] \
                                 [dict get $empty_cfg w] [dict get $empty_cfg h]
                    }
                    dict set slot_occupant $empty_slot $occupant_id

                    # Move floating window to this slot (if not active)
                    if {$win_id ne $active_id} {
                        wm::move $win_id 0 $slot_x $slot_y $slot_w $slot_h
                    }
                    dict set slot_occupant $best_slot $win_id

                    set status "Swapped windows"
                }
            }
            # else: too far from occupied slot, do nothing (don't fight user)
        } else {
            # Slot is empty - snap to it (if not active)
            if {$win_id ne $active_id} {
                wm::move $win_id 0 $slot_x $slot_y $slot_w $slot_h
            }
            dict set slot_occupant $best_slot $win_id
        }
    }
}

# Monitor loop
proc monitor_loop {} {
    global monitoring monitor_interval

    if {!$monitoring} return

    catch {assign_and_snap_slots}
    after $monitor_interval monitor_loop
}

# Toggle monitoring
proc toggle_monitoring {} {
    global monitoring status
    set monitoring [expr {!$monitoring}]
    update_monitor_button
    if {$monitoring} {
        set status "Monitoring ON"
        after idle monitor_loop
    } else {
        set status "Monitoring OFF"
    }
}

# Update monitor button appearance
proc update_monitor_button {} {
    global monitoring
    if {$monitoring} {
        .btns.monitor configure -text "Monitor: ON" -style Monitor.On.TButton
    } else {
        .btns.monitor configure -text "Monitor: OFF" -style Monitor.Off.TButton
    }
    update idletasks
}

# Main window setup
wm title . "Wider - Slot Editor"
wm resizable . 1 1
wm minsize . 600 300
tk appname wider

# Status variable
set status "Ready"

# Track window data by id
set window_data {}

# Current row widgets by window id
set row_widgets {}

# ========== Window List Functions ==========

# Get currently focused window ID using TkX (no exec)
proc get_focused_window {} {
    return [TkX::active_window]
}

# Normalize hex window ID (strip leading zeros after 0x)
proc normalize_id {id} {
    if {[string match "0x*" $id]} {
        return [format "0x%x" [scan $id "%x"]]
    }
    return $id
}

# Highlight focused window row
proc update_focus_highlight {} {
    global row_widgets

    set focused [normalize_id [get_focused_window]]
    set focus_bg "#cce5ff"  ;# light blue
    set normal_bg "#ffffff"

    dict for {id widgets} $row_widgets {
        set norm_id [normalize_id $id]
        set bg [expr {$norm_id eq $focused ? $focus_bg : $normal_bg}]
        catch {
            [dict get $widgets frame] configure -background $bg
            [dict get $widgets class] configure -background $bg
            [dict get $widgets title] configure -background $bg
        }
    }
}

# Focus highlight loop
proc focus_highlight_loop {} {
    catch {update_focus_highlight}
    after 250 focus_highlight_loop
}

# Refresh window list
proc refresh_window_list {} {
    global status window_data row_widgets
    variable wm::slots

    # Clear existing rows
    foreach child [winfo children .grid.inner] {
        destroy $child
    }
    set window_data {}
    set row_widgets {}

    # Filter and collect windows
    set skip_classes {Xfdesktop Xfce4-panel Plank Polybar Xfwm4 Wrapper-2.0}
    set filtered_wins {}
    foreach win [wm::windows] {
        set class [dict get $win class]
        set desktop [dict get $win desktop]
        if {$class eq "Wider.tcl"} continue
        if {$desktop eq "-1"} continue
        if {$class in $skip_classes} continue
        lappend filtered_wins $win
    }

    # Sort by role (empty roles last)
    set filtered_wins [lsort -command {apply {{a b} {
        set ra [dict get $a role]
        set rb [dict get $b role]
        if {$ra eq "" && $rb eq ""} { return 0 }
        if {$ra eq ""} { return 1 }
        if {$rb eq ""} { return -1 }
        return [string compare $ra $rb]
    }}} $filtered_wins]

    set row 0
    foreach win $filtered_wins {
        set id [dict get $win id]
        set class [dict get $win class]
        set role [dict get $win role]
        set desktop [dict get $win desktop]
        set x [dict get $win x]
        set y [dict get $win y]
        set w [dict get $win w]
        set h [dict get $win h]
        set title [dict get $win title]
        set geom "${w}x${h}+${x}+${y}"

        # Check if managed (has matching slot)
        set slot [wm::find_slot_for_window $id]
        set managed [expr {$slot ne ""}]

        # Get command from slot config if managed
        set command ""
        if {$managed && [dict exists $wm::slots $slot]} {
            set cfg [dict get $wm::slots $slot]
            if {[dict exists $cfg command]} {
                set command [dict get $cfg command]
            }
        }

        # Store window data
        dict set window_data $id [dict create \
            class $class role $role geom $geom title $title \
            x $x y $y w $w h $h managed $managed slot $slot command $command]

        # Create row frame
        set rf .grid.inner.r$row
        frame $rf -background white
        grid $rf -row $row -column 0 -sticky ew

        # Managed checkbutton
        set var "::managed_$id"
        set $var $managed
        checkbutton $rf.cb -variable $var -command [list on_managed_toggle $id] \
            -background white -activebackground white

        # Role entry
        entry $rf.role -width 18
        $rf.role insert 0 $role
        bind $rf.role <Return> [list on_role_change $id]
        bind $rf.role <FocusOut> [list on_role_change $id]

        # Class label
        label $rf.class -text $class -width 14 -anchor w -background white

        # Geometry entry
        entry $rf.geom -width 16
        $rf.geom insert 0 $geom
        bind $rf.geom <Return> [list on_geom_change $id]
        bind $rf.geom <FocusOut> [list on_geom_change $id]

        # Command entry
        entry $rf.cmd -width 24
        $rf.cmd insert 0 $command
        bind $rf.cmd <Return> [list on_command_change $id]
        bind $rf.cmd <FocusOut> [list on_command_change $id]

        # Title label (truncated)
        set short_title [string range $title 0 25]
        if {[string length $title] > 25} { append short_title "..." }
        label $rf.title -text $short_title -anchor w -background white

        # Grid the widgets
        grid $rf.cb $rf.role $rf.class $rf.geom $rf.cmd $rf.title -sticky w -padx 2 -pady 1
        grid columnconfigure $rf 5 -weight 1

        # Store widget references
        dict set row_widgets $id [dict create \
            frame $rf cb $rf.cb role $rf.role class $rf.class \
            geom $rf.geom cmd $rf.cmd title $rf.title var $var]

        incr row
    }

    # Update scroll region
    update idletasks
    .grid configure -scrollregion [.grid bbox all]

    set status "Refreshed $row windows"
}

# Checkbox toggle handler
proc on_managed_toggle {id} {
    global window_data status row_widgets

    if {![dict exists $window_data $id]} return

    set var [dict get [dict get $row_widgets $id] var]
    set managed [set $var]
    set win [dict get $window_data $id]
    set class [dict get $win class]
    set role [dict get $win role]

    if {!$managed} {
        # Unmanage - remove from slots
        set slot [dict get $win slot]
        if {$slot ne ""} {
            dict unset wm::slots $slot
        }
        dict set window_data $id managed 0
        dict set window_data $id slot ""
        set status "Removed $class from slots"
    } else {
        # Manage - add to slots
        if {$role eq ""} {
            set role [string tolower $class]
            wm::set_role $id $role
            dict set window_data $id role $role
            [dict get [dict get $row_widgets $id] role] delete 0 end
            [dict get [dict get $row_widgets $id] role] insert 0 $role
        }
        set slot_name [string tolower $role]
        # Preserve existing command if any
        set cmd [dict get $win command]
        set slot_dict [dict create \
            role $role class $class \
            x [dict get $win x] y [dict get $win y] \
            w [dict get $win w] h [dict get $win h]]
        if {$cmd ne ""} {
            dict set slot_dict command $cmd
        }
        dict set wm::slots $slot_name $slot_dict
        dict set window_data $id managed 1
        dict set window_data $id slot $slot_name
        set status "Added $class to slots"
    }

    save_all
}

# Role change handler
proc on_role_change {id} {
    global window_data status row_widgets

    if {![dict exists $window_data $id]} return

    set entry [dict get [dict get $row_widgets $id] role]
    set new_role [string trim [$entry get]]
    set win [dict get $window_data $id]
    set old_role [dict get $win role]

    if {$new_role eq $old_role} return
    if {$new_role eq ""} return

    set class [dict get $win class]

    # Update window role
    wm::set_role $id $new_role
    dict set window_data $id role $new_role

    # Update or create slot
    set old_slot [dict get $win slot]
    if {$old_slot ne "" && [dict exists $wm::slots $old_slot]} {
        dict unset wm::slots $old_slot
    }

    set slot_name [string tolower $new_role]
    # Preserve existing command if any
    set cmd [dict get $win command]
    set slot_dict [dict create \
        role $new_role class $class \
        x [dict get $win x] y [dict get $win y] \
        w [dict get $win w] h [dict get $win h]]
    if {$cmd ne ""} {
        dict set slot_dict command $cmd
    }
    dict set wm::slots $slot_name $slot_dict

    dict set window_data $id managed 1
    dict set window_data $id slot $slot_name

    # Update checkbox
    set var [dict get [dict get $row_widgets $id] var]
    set $var 1

    set status "Role: $new_role"
    save_all
}

# Geometry change handler
proc on_geom_change {id} {
    global window_data status row_widgets

    if {![dict exists $window_data $id]} return

    set entry [dict get [dict get $row_widgets $id] geom]
    set new_geom [string trim [$entry get]]
    set win [dict get $window_data $id]
    set old_geom [dict get $win geom]

    if {$new_geom eq $old_geom} return

    # Parse geometry
    if {[catch {wm::parse_geometry $new_geom} parsed]} {
        set status "Invalid geometry: $new_geom"
        $entry delete 0 end
        $entry insert 0 $old_geom
        return
    }

    set x [dict get $parsed x]
    set y [dict get $parsed y]
    set w [dict get $parsed w]
    set h [dict get $parsed h]

    # Move/resize the window
    wm::move $id $x $y $w $h

    # Update window_data
    dict set window_data $id x $x
    dict set window_data $id y $y
    dict set window_data $id w $w
    dict set window_data $id h $h
    dict set window_data $id geom $new_geom

    # Update slot if managed
    set slot [dict get $win slot]
    if {$slot ne "" && [dict exists $wm::slots $slot]} {
        dict set wm::slots $slot x $x
        dict set wm::slots $slot y $y
        dict set wm::slots $slot w $w
        dict set wm::slots $slot h $h
        save_all
    }

    set status "Geometry: $new_geom"
}

# Command change handler
proc on_command_change {id} {
    global window_data status row_widgets
    variable wm::slots

    if {![dict exists $window_data $id]} return

    set entry [dict get [dict get $row_widgets $id] cmd]
    set new_cmd [string trim [$entry get]]
    set win [dict get $window_data $id]
    set old_cmd [dict get $win command]

    if {$new_cmd eq $old_cmd} return

    # Update window_data
    dict set window_data $id command $new_cmd

    # Update slot if managed
    set slot [dict get $win slot]
    if {$slot ne "" && [dict exists $wm::slots $slot]} {
        if {$new_cmd eq ""} {
            # Remove command from slot
            dict unset wm::slots $slot command
        } else {
            dict set wm::slots $slot command $new_cmd
        }
        save_all
    }

    set status "Command: $new_cmd"
}

# Save slots and regenerate autostart
proc save_all {} {
    global status
    wm::save_slots
    wm::generate_autostart
    set status "Saved slots and autostart files"
}

# Arrange button
proc do_arrange {} {
    global status
    try {
        set count [wm::arrange_all]
        set status "Arranged $count windows"
        refresh_window_list
    } on error {msg} {
        set status "Error: $msg"
    }
}

# Launch button
proc do_launch {} {
    global status
    try {
        set count [wm::launch_all]
        if {$count > 0} {
            set status "Launched $count apps"
            after 1000 refresh_window_list
        } else {
            set status "All apps running"
        }
    } on error {msg} {
        set status "Error: $msg"
    }
}

# Snap button - save current window positions to slot config
# Pauses monitoring to avoid race condition
proc do_snap {} {
    global status monitoring
    variable wm::slots

    # Pause monitoring during snap
    set was_monitoring $monitoring
    set monitoring 0

    set count 0
    set windows [wm::windows]

    # For each window with a role, update its slot geometry
    foreach win $windows {
        set role [dict get $win role]
        if {$role eq ""} continue

        set x [dict get $win x]
        set y [dict get $win y]
        set w [dict get $win w]
        set h [dict get $win h]

        # Find matching slot by role (try lowercase first, then exact)
        set slot_name [string tolower $role]
        if {[dict exists $wm::slots $slot_name]} {
            dict set wm::slots $slot_name x $x
            dict set wm::slots $slot_name y $y
            dict set wm::slots $slot_name w $w
            dict set wm::slots $slot_name h $h
            incr count
        } elseif {[dict exists $wm::slots $role]} {
            dict set wm::slots $role x $x
            dict set wm::slots $role y $y
            dict set wm::slots $role w $w
            dict set wm::slots $role h $h
            incr count
        }
    }

    if {$count > 0} {
        save_all
        set status "Snapped $count window positions"
        refresh_window_list
    } else {
        set status "No managed windows to snap"
    }

    # Resume monitoring
    set monitoring $was_monitoring
}

# ========== UI Setup ==========

# Styles
ttk::style configure Monitor.On.TButton -foreground darkgreen
ttk::style configure Monitor.Off.TButton -foreground gray

# Main frame
ttk::frame .f -padding 5
grid .f -sticky nsew
grid columnconfigure . 0 -weight 1
grid rowconfigure . 0 -weight 1

# Header row
frame .hdr -background #e0e0e0
label .hdr.cb -text "" -width 3 -background #e0e0e0
label .hdr.role -text "Role" -width 18 -anchor w -background #e0e0e0 -font {TkDefaultFont 9 bold}
label .hdr.class -text "Class" -width 14 -anchor w -background #e0e0e0 -font {TkDefaultFont 9 bold}
label .hdr.geom -text "Geometry" -width 16 -anchor w -background #e0e0e0 -font {TkDefaultFont 9 bold}
label .hdr.cmd -text "Command" -width 24 -anchor w -background #e0e0e0 -font {TkDefaultFont 9 bold}
label .hdr.title -text "Title" -anchor w -background #e0e0e0 -font {TkDefaultFont 9 bold}
grid .hdr.cb .hdr.role .hdr.class .hdr.geom .hdr.cmd .hdr.title -sticky w -padx 2 -pady 3
grid columnconfigure .hdr 5 -weight 1

# Scrollable canvas for window grid
canvas .grid -background white -yscrollcommand {.vsb set} -highlightthickness 0
ttk::scrollbar .vsb -orient vertical -command {.grid yview}

# Inner frame for grid rows
frame .grid.inner -background white
.grid create window 0 0 -anchor nw -window .grid.inner -tags inner

# Configure canvas scrolling
bind .grid.inner <Configure> {
    .grid configure -scrollregion [.grid bbox all]
}
bind .grid <MouseWheel> {
    .grid yview scroll [expr {-%D/120}] units
}
bind .grid <Button-4> {.grid yview scroll -3 units}
bind .grid <Button-5> {.grid yview scroll 3 units}

# Button bar
ttk::frame .btns
ttk::button .btns.refresh -text "Refresh" -command refresh_window_list
ttk::button .btns.snap -text "Snap" -command do_snap
ttk::button .btns.arrange -text "Arrange" -command do_arrange
ttk::button .btns.launch -text "Launch" -command do_launch
ttk::button .btns.monitor -text "Monitor: ON" -command toggle_monitoring -style Monitor.On.TButton

# Status bar
ttk::label .status -textvariable status -foreground gray -anchor w

# Layout
grid .hdr -in .f -row 0 -column 0 -columnspan 2 -sticky ew
grid .grid -in .f -row 1 -column 0 -sticky nsew
grid .vsb -in .f -row 1 -column 1 -sticky ns
grid .btns -in .f -row 2 -column 0 -columnspan 2 -sticky ew -pady 5
grid .status -in .f -row 3 -column 0 -columnspan 2 -sticky ew

pack .btns.refresh .btns.snap .btns.arrange .btns.launch .btns.monitor -side left -padx 3

grid columnconfigure .f 0 -weight 1
grid rowconfigure .f 1 -weight 1

# Keep window on top (optional - can be toggled)
# wm attributes . -topmost 1

# Initial setup
after idle {
    update idletasks

    # Position window
    set sw [winfo screenwidth .]
    wm geometry . 700x400+[expr {$sw - 750}]+50

    # Set _NET_WM_PID
    after 100 {
        set frame [wm frame .]
        if {$frame ne "0x0"} {
            catch {exec xprop -id $frame -f _NET_WM_PID 32c -set _NET_WM_PID [pid]}
        }
    }

    # Load window list
    refresh_window_list

    # Start monitoring loop (stateless - runs every 500ms)
    after 200 monitor_loop

    # Start focus highlight loop
    after 300 focus_highlight_loop
}
