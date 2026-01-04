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
set snapback_interval 2000  ;# ms - how often to snap back
set window_positions {}   ;# id -> {x y slot last_moved}
set last_swap_time 0      ;# time of last swap (ms) - skip checks briefly after swap

# Track window positions for managed windows
proc update_positions {} {
    global window_positions
    set now [clock milliseconds]
    set new_positions {}

    foreach win [wm::windows] {
        set id [dict get $win id]
        set x [dict get $win x]
        set y [dict get $win y]

        # Preserve existing slot assignment to enable swap detection
        # Only calculate slot for new windows
        if {[dict exists $window_positions $id]} {
            set slot [dict get [dict get $window_positions $id] slot]
        } else {
            set slot [wm::find_slot_for_window $id]
        }
        if {$slot eq ""} continue

        # Check if window moved since last check
        set last_moved $now
        if {[dict exists $window_positions $id]} {
            set prev [dict get $window_positions $id]
            set dx [expr {abs($x - [dict get $prev x])}]
            set dy [expr {abs($y - [dict get $prev y])}]
            if {$dx < 10 && $dy < 10} {
                # Didn't move - keep old last_moved time
                set last_moved [dict get $prev last_moved]
            }
        }

        dict set new_positions $id [dict create \
            x $x y $y \
            w [dict get $win w] h [dict get $win h] \
            slot $slot last_moved $last_moved]
    }

    set window_positions $new_positions
}

# Swap slot assignments for two windows after a successful swap
proc swap_slot_assignments {slot1 slot2} {
    global window_positions

    # Find window IDs assigned to each slot
    set id1 ""
    set id2 ""
    dict for {id pos} $window_positions {
        set slot [dict get $pos slot]
        if {$slot eq $slot1} { set id1 $id }
        if {$slot eq $slot2} { set id2 $id }
    }

    # Swap their slot assignments
    if {$id1 ne "" && $id2 ne ""} {
        dict set window_positions $id1 slot $slot2
        dict set window_positions $id2 slot $slot1
    }
}

# Check for window movements and trigger swaps
proc check_movements {} {
    global window_positions swap_threshold status last_swap_time
    variable wm::slots

    # Skip if a swap just happened
    if {[clock milliseconds] - $last_swap_time < 3000} return

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

        # Window moved - check if it's near another slot with same role
        set prev_cfg [dict get $wm::slots $prev_slot]
        set prev_role [dict get $prev_cfg role]
        dict for {other_slot cfg} $wm::slots {
            if {$other_slot eq $prev_slot} continue
            # Only consider slots with matching role
            if {![dict exists $cfg role] || [dict get $cfg role] ne $prev_role} continue

            set dist [wm::slot_distance $win $other_slot]
            if {$dist < $swap_threshold} {
                # Find other window ID from window_positions
                set other_id ""
                dict for {wid wpos} $window_positions {
                    if {[dict get $wpos slot] eq $other_slot} {
                        set other_id $wid
                        break
                    }
                }
                if {$other_id eq ""} continue

                # Trigger swap!
                set status "Swapping $prev_slot <-> $other_slot"
                if {[wm::swap_slots $prev_slot $other_slot $id $other_id]} {
                    swap_slot_assignments $prev_slot $other_slot
                    set last_swap_time [clock milliseconds]
                }
                update_positions
                return
            }
        }
    }

    # Update positions for next iteration
    update_positions
}

# Snap back windows that haven't moved recently
# Also checks for swap-on-rest: if window is near another slot, trigger swap
proc snapback_idle_windows {} {
    global window_positions status monitoring swap_threshold last_swap_time
    variable wm::slots

    if {!$monitoring} return

    # Skip if a swap just happened (give wmctrl time to update)
    set now [clock milliseconds]
    if {$now - $last_swap_time < 3000} return
    set idle_threshold 2000   ;# must be stationary for 2 seconds
    set snap_distance 100     ;# only snap if within this distance of slot
    set snapped 0

    dict for {id pos} $window_positions {
        set last_moved [dict get $pos last_moved]
        set idle_time [expr {$now - $last_moved}]

        # Skip if window moved recently (being dragged)
        if {$idle_time < $idle_threshold} continue

        set current_slot [dict get $pos slot]
        if {![dict exists $wm::slots $current_slot]} continue

        # Build pseudo-window dict for distance calculation
        set win [dict create x [dict get $pos x] y [dict get $pos y] \
                             w [dict get $pos w] h [dict get $pos h]]

        # Check if window is near a DIFFERENT slot with SAME role (swap candidate)
        set current_cfg [dict get $wm::slots $current_slot]
        set current_role [dict get $current_cfg role]
        set swap_target ""
        set min_dist 999999
        dict for {other_slot cfg} $wm::slots {
            if {$other_slot eq $current_slot} continue
            # Only consider slots with matching role
            if {![dict exists $cfg role] || [dict get $cfg role] ne $current_role} continue
            set dist [wm::slot_distance $win $other_slot]
            if {$dist < $swap_threshold && $dist < $min_dist} {
                set min_dist $dist
                set swap_target $other_slot
            }
        }

        if {$swap_target ne ""} {
            # Find window IDs from window_positions (not proximity)
            set other_id ""
            dict for {wid wpos} $window_positions {
                if {[dict get $wpos slot] eq $swap_target} {
                    set other_id $wid
                    break
                }
            }
            if {$other_id eq ""} continue

            # Trigger swap instead of snapback
            set status "Swapping $current_slot <-> $swap_target"
            if {[wm::swap_slots $current_slot $swap_target $id $other_id]} {
                # Swap slot assignments in window_positions
                swap_slot_assignments $current_slot $swap_target
                set last_swap_time [clock milliseconds]
            }
            update_positions
            return  ;# Process one swap per cycle
        }

        # No swap - check if should snap back
        set cfg [dict get $wm::slots $current_slot]
        set slot_x [dict get $cfg x]
        set slot_y [dict get $cfg y]
        set dx [expr {abs([dict get $pos x] - $slot_x)}]
        set dy [expr {abs([dict get $pos y] - $slot_y)}]
        set displacement [expr {sqrt($dx*$dx + $dy*$dy)}]

        # Only snap back if window is close to slot but not exactly on it
        # If window is far away, user intentionally moved it - don't snap
        if {$displacement > 20 && $displacement < $snap_distance} {
            wm::arrange_slot $current_slot
            incr snapped
        }
    }

    if {$snapped > 0} {
        set status "Snapped $snapped window(s) to slots"
        update_positions
    }
}

# Snapback loop (runs every 5 seconds)
proc snapback_loop {} {
    global monitoring snapback_interval

    if {$monitoring} {
        catch {snapback_idle_windows}
    }
    after $snapback_interval snapback_loop
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

# Get currently focused window ID
proc get_focused_window {} {
    if {[catch {exec xprop -root _NET_ACTIVE_WINDOW} result]} {
        return ""
    }
    if {[regexp {window id # (0x[0-9a-fA-F]+)} $result -> id]} {
        return $id
    }
    return ""
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
        update_positions
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

# Update monitor button reference
proc update_monitor_button {} {
    global monitoring
    if {$monitoring} {
        .btns.monitor configure -text "Monitor: ON" -style Monitor.On.TButton
    } else {
        .btns.monitor configure -text "Monitor: OFF" -style Monitor.Off.TButton
    }
}

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

    # Start monitoring
    after 200 {
        update_positions
        monitor_loop
    }

    # Start snapback loop (every 2 seconds)
    after 2000 snapback_loop

    # Start focus highlight loop
    after 300 focus_highlight_loop
}
