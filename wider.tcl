#!/home/john/bin/wish9.1
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

# Resolve symlinks to find actual script location
set script [file normalize [info script]]
while {[file type $script] eq "link"} {
    set script [file join [file dirname $script] [file readlink $script]]
}
set script_dir [file dirname [file normalize $script]]
lappend auto_path [file join $script_dir tkx lib]
source [file join $script_dir wmctrl.tcl]

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
set pending_snap ""
set pending_geom {}

proc assign_and_snap_slots {} {
    global status swap_threshold pending_snap pending_geom

    set windows [wm::windows]
    set active_id [TkX::active_window]

    # Group windows by role
    set by_role {}
    foreach win $windows {
        set role [dict get $win role]
        if {$role eq ""} continue
        dict lappend by_role $role $win
    }

    # Sort slots left-to-right, top-to-bottom
    set sorted_slots [lsort -command {apply {{a b} {
        set cmp [expr {[dict get $a x] - [dict get $b x]}]
        if {$cmp != 0} { return $cmp }
        expr {[dict get $a y] - [dict get $b y]}
    }}} $wm::slots]

    set assigned {}      ;# window ids already assigned
    set unassigned {}    ;# {id win_data slot} - displaced windows with target slot
    set empty_slots {}   ;# slots with no candidate

    foreach slot $sorted_slots {
        dict with slot {
            if {![info exists role]} continue

            # Get candidates (same role, not yet assigned)
            set candidates {}
            if {[dict exists $by_role $role]} {
                foreach win [dict get $by_role $role] {
                    set id [dict get $win id]
                    if {$id ni $assigned} {
                        set wx [dict get $win x]
                        set wy [dict get $win y]
                        set dist [expr {$wx == $x && $wy == $y ? 0 : [wm::slot_distance_to $win $slot]}]
                        lappend candidates [list $id $dist $win]
                    }
                }
            }

            if {[llength $candidates] == 0} {
                lappend empty_slots $slot
                continue
            }

            set candidates [lsort -real -index 1 $candidates]
            lassign [lindex $candidates 0] first_id first_dist first_win

            if {$first_dist == 0} {
                # Window is exactly in slot - check for swap
                if {[llength $candidates] > 1} {
                    lassign [lindex $candidates 1] second_id second_dist second_win
                    if {$second_dist <= $swap_threshold} {
                        lappend assigned $second_id
                        lappend unassigned [list $first_id $first_win]
                        # Move second window into slot, or defer if being dragged
                        set hints [wm::get_size_hints $second_id]
                        lassign [wm::units_to_pixels $w $h $hints] pw ph
                        if {$second_id ne $active_id} {
                            wm::move $second_id 0 $x $y $pw $ph
                        } else {
                            set pending_snap $second_id
                            set pending_geom [list $x $y $pw $ph]
                        }
                        set status "Swapped"
                        continue
                    }
                }
                lappend assigned $first_id
            } elseif {$first_dist <= $swap_threshold} {
                lappend assigned $first_id
                if {$first_id ne $active_id} {
                    # Convert slot units to pixels
                    set hints [wm::get_size_hints $first_id]
                    lassign [wm::units_to_pixels $w $h $hints] pw ph
                    wm::move $first_id 0 $x $y $pw $ph
                }
            } else {
                # No window close enough - slot is empty
                lappend empty_slots $slot
            }
        }
    }

    # Place displaced windows in empty slots
    foreach entry $unassigned {
        lassign $entry win_id win_data
        if {[llength $empty_slots] == 0} break

        set win_role [dict get $win_data role]
        set best_slot {}
        set best_dist 999999

        foreach slot $empty_slots {
            if {[dict get $slot role] ne $win_role} continue
            set dist [wm::slot_distance_to $win_data $slot]
            if {$dist < $best_dist} {
                set best_dist $dist
                set best_slot $slot
            }
        }

        if {[dict size $best_slot] > 0} {
            set idx [lsearch -exact $empty_slots $best_slot]
            set empty_slots [lreplace $empty_slots $idx $idx]
            if {$win_id ne $active_id} {
                dict with best_slot {
                    # Convert slot units to pixels
                    set hints [wm::get_size_hints $win_id]
                    lassign [wm::units_to_pixels $w $h $hints] pw ph
                    wm::move $win_id 0 $x $y $pw $ph
                }
            }
        }
    }

    # Complete pending snap when mouse released
    if {$pending_snap ne ""} {
        set pstate [TkX::pointer_state]
        if {![dict get $pstate button1] && ![dict get $pstate button2] && ![dict get $pstate button3]} {
            lassign $pending_geom x y w h
            wm::move $pending_snap 0 $x $y $w $h
            set pending_snap ""
        }
    }
}

proc monitor_loop {} {
    global monitoring monitor_interval

    if {!$monitoring} return

    catch {assign_and_snap_slots}
    after $monitor_interval monitor_loop
}

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

proc update_monitor_button {} {
    global monitoring
    if {$monitoring} {
        .btns.monitor configure -text "Monitor: ON" -style Monitor.On.TButton
    } else {
        .btns.monitor configure -text "Monitor: OFF" -style Monitor.Off.TButton
    }
    update idletasks
}

wm title . "Wider - Slot Editor"
wm resizable . 1 1
tk appname wider
set status "Ready"

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

    # Assign slots to windows (1:1 matching, closest first)
    set claimed_slots {}  ;# indices of slots already claimed
    set win_to_slot {}    ;# window id -> slot dict

    foreach win $filtered_wins {
        set id [dict get $win id]
        set win_role [dict get $win role]

        set best_slot {}
        set best_idx -1
        set best_dist 999999

        set idx -1
        foreach slot $wm::slots {
            incr idx
            if {$idx in $claimed_slots} continue
            # Match by role
            if {$win_role eq "" || ![dict exists $slot role] || [dict get $slot role] ne $win_role} continue
            set dist [wm::slot_distance_to $win $slot]
            if {$dist < $best_dist} {
                set best_dist $dist
                set best_slot $slot
                set best_idx $idx
            }
        }

        if {$best_idx >= 0} {
            lappend claimed_slots $best_idx
            dict set win_to_slot $id $best_slot
        }
    }

    set row 0
    foreach win $filtered_wins {
        set id [dict get $win id]
        set class [dict get $win class]
        set role [dict get $win role]
        set desktop [dict get $win desktop]
        set x [dict get $win x]
        set y [dict get $win y]
        set pw [dict get $win w]
        set ph [dict get $win h]
        set title [dict get $win title]

        # Convert pixel dimensions to app units for display (chars for terminals)
        set hints [wm::get_size_hints $id]
        lassign [wm::pixels_to_units $pw $ph $hints] w h
        set geom "${w}x${h}+${x}+${y}"

        # Check if managed (has claimed slot)
        set slot [expr {[dict exists $win_to_slot $id] ? [dict get $win_to_slot $id] : {}}]
        set managed [expr {[dict size $slot] > 0}]

        # Get command from slot config, or fall back to window cmdline
        set command ""
        if {$managed && [dict exists $slot command]} {
            set command [dict get $slot command]
        } elseif {[dict exists $win cmdline]} {
            set command [dict get $win cmdline]
        }

        # Store window data
        dict set window_data $id [dict create \
            class $class role $role geom $geom title $title \
            x $x y $y w $w h $h managed $managed command $command]

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
        entry $rf.role -width 16
        $rf.role insert 0 $role
        bind $rf.role <Return> [list on_role_change $id]
        bind $rf.role <FocusOut> [list on_role_change $id]

        # Class label
        label $rf.class -text $class -width 14 -anchor w -background white

        # Geometry entry
        entry $rf.geom -width 20
        $rf.geom insert 0 $geom
        bind $rf.geom <Return> [list on_geom_change $id]
        bind $rf.geom <FocusOut> [list on_geom_change $id]

        # Command entry
        entry $rf.cmd -width 30
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

proc on_managed_toggle {id} {
    global window_data status row_widgets

    if {![dict exists $window_data $id]} return

    set var [dict get [dict get $row_widgets $id] var]
    set managed [set $var]
    set win [dict get $window_data $id]
    set class [dict get $win class]
    set role [dict get $win role]
    set x [dict get $win x]
    set y [dict get $win y]

    if {!$managed} {
        # Unmanage - remove matching slot
        set idx [wm::find_slot_index $role $x $y]
        if {$idx >= 0} {
            wm::remove_slot_at $idx
        }
        dict set window_data $id managed 0
        set status "Removed $class from slots"
    } else {
        # Manage - add slot
        if {$role eq ""} {
            set role [string tolower $class]
            wm::set_role $id $role
            dict set window_data $id role $role
            [dict get [dict get $row_widgets $id] role] delete 0 end
            [dict get [dict get $row_widgets $id] role] insert 0 $role
        }
        set cmd [dict get $win command]
        set slot_dict [dict create \
            role $role class $class \
            x $x y $y \
            w [dict get $win w] h [dict get $win h]]
        if {$cmd ne ""} {
            dict set slot_dict command $cmd
        }
        wm::add_slot $slot_dict
        dict set window_data $id managed 1
        set status "Added $class to slots"
    }

    save_all
}

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
    set x [dict get $win x]
    set y [dict get $win y]

    # Update window role
    wm::set_role $id $new_role
    dict set window_data $id role $new_role

    # Remove old slot if exists
    set old_idx [wm::find_slot_index $old_role $x $y]
    if {$old_idx >= 0} {
        wm::remove_slot_at $old_idx
    }

    # Create new slot
    set cmd [dict get $win command]
    set slot_dict [dict create \
        role $new_role class $class \
        x $x y $y \
        w [dict get $win w] h [dict get $win h]]
    if {$cmd ne ""} {
        dict set slot_dict command $cmd
    }
    wm::add_slot $slot_dict

    dict set window_data $id managed 1

    # Update checkbox
    set var [dict get [dict get $row_widgets $id] var]
    set $var 1

    set status "Role: $new_role"
    save_all
}

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

    set new_x [dict get $parsed x]
    set new_y [dict get $parsed y]
    set new_w [dict get $parsed w]
    set new_h [dict get $parsed h]

    # Convert app units to pixels for move (user enters app units)
    set hints [wm::get_size_hints $id]
    lassign [wm::units_to_pixels $new_w $new_h $hints] pw ph

    # Move/resize the window with pixel dimensions
    wm::move $id $new_x $new_y $pw $ph

    # Update slot with app units (as entered by user)
    set role [dict get $win role]
    set old_x [dict get $win x]
    set old_y [dict get $win y]
    if {[wm::update_slot_geometry $role $old_x $old_y $new_x $new_y $new_w $new_h]} {
        save_all
    }

    # Update window_data with app units
    dict set window_data $id x $new_x
    dict set window_data $id y $new_y
    dict set window_data $id w $new_w
    dict set window_data $id h $new_h
    dict set window_data $id geom $new_geom

    set status "Geometry: $new_geom"
}

# Command change handler - sets WM_COMMAND on the window
proc on_command_change {id} {
    global window_data status row_widgets

    if {![dict exists $window_data $id]} return

    set entry [dict get [dict get $row_widgets $id] cmd]
    set new_cmd [string trim [$entry get]]
    set win [dict get $window_data $id]
    set old_cmd [dict get $win command]

    if {$new_cmd eq $old_cmd} return

    # Set WM_COMMAND on the actual window
    if {$new_cmd ne ""} {
        wm::set_command $id $new_cmd
    }

    # Update window_data
    dict set window_data $id command $new_cmd

    set status "Set WM_COMMAND: $new_cmd"
}

proc save_all {} {
    global status window_data

    # Rebuild slots from currently managed windows
    set wm::slots {}
    dict for {id win} $window_data {
        if {![dict get $win managed]} continue
        set slot [dict create \
            role [dict get $win role] \
            class [dict get $win class] \
            x [dict get $win x] \
            y [dict get $win y] \
            w [dict get $win w] \
            h [dict get $win h]]
        set cmd [dict get $win command]
        if {$cmd ne ""} {
            dict set slot command $cmd
        }
        lappend wm::slots $slot
    }

    wm::save_slots
    wm::generate_autostart
    set status "Saved slots and autostart files"
}

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
# Creates slots for windows that don't have one
proc do_snap {} {
    global status monitoring

    set was_monitoring $monitoring
    set monitoring 0

    set count 0
    set windows [wm::windows]
    set claimed_slots {}  ;# slot indices already matched to a window

    # For each window with a role, find or create a slot
    foreach win $windows {
        set role [dict get $win role]
        if {$role eq ""} continue

        set id [dict get $win id]
        set class [dict get $win class]
        set x [dict get $win x]
        set y [dict get $win y]
        set pw [dict get $win w]
        set ph [dict get $win h]
        set cmd [dict get $win cmdline]

        # Convert pixel dimensions to app units (chars for terminals)
        set hints [wm::get_size_hints $id]
        lassign [wm::pixels_to_units $pw $ph $hints] w h

        # Find closest unclaimed slot with matching role
        set best_slot {}
        set best_idx -1
        set best_dist 999999

        set idx -1
        foreach slot $wm::slots {
            incr idx
            if {$idx in $claimed_slots} continue
            # Match by role
            if {![dict exists $slot role] || [dict get $slot role] ne $role} continue
            set dist [wm::slot_distance_to $win $slot]
            if {$dist < $best_dist} {
                set best_dist $dist
                set best_slot $slot
                set best_idx $idx
            }
        }

        if {$best_idx >= 0} {
            # Update existing slot
            lappend claimed_slots $best_idx
            set slot $best_slot
            dict set slot x $x
            dict set slot y $y
            dict set slot w $w
            dict set slot h $h
            if {$cmd ne ""} {
                dict set slot command $cmd
            }
            wm::set_slot $best_idx $slot
            incr count
        } else {
            # Create new slot
            set slot_dict [dict create role $role class $class x $x y $y w $w h $h]
            if {$cmd ne ""} {
                dict set slot_dict command $cmd
            }
            wm::add_slot $slot_dict
            incr count
        }
    }

    if {$count > 0} {
        save_all
        set status "Snapped $count windows"
        refresh_window_list
    } else {
        set status "No windows to snap"
    }

    set monitoring $was_monitoring
}

# ========== UI Setup ==========

# Styles
ttk::style configure Monitor.On.TButton -foreground darkgreen
ttk::style configure Monitor.Off.TButton -foreground gray

# Alt-C/Alt-V copy/paste bindings for entry widgets
bind Entry <Alt-c> {
    if {[%W selection present]} {
        clipboard clear
        clipboard append [string range [%W get] [%W index sel.first] [expr {[%W index sel.last] - 1}]]
    }
}
bind Entry <Alt-v> {
    if {[catch {set clip [clipboard get]}] == 0} {
        if {[%W selection present]} {
            %W delete sel.first sel.last
        }
        %W insert insert $clip
    }
}

# Main frame
ttk::frame .f -padding 5
grid .f -sticky nsew
grid columnconfigure . 0 -weight 1
grid rowconfigure . 0 -weight 1

# Collapsible card state
set card_expanded 0

set saved_height 400

proc toggle_card {} {
    global card_expanded saved_height
    set card_expanded [expr {!$card_expanded}]
    set w [winfo width .]
    if {$card_expanded} {
        grid .card -in .f -row 1 -column 0 -sticky nsew
        .btns.toggle configure -text "▼"
        wm minsize . 600 300
        wm geometry . ${w}x${saved_height}
    } else {
        set saved_height [winfo height .]
        grid forget .card
        .btns.toggle configure -text "▶"
        update idletasks
        wm minsize . 600 0
        wm geometry . ${w}x[winfo reqheight .]
    }
}

# Button bar (at top)
ttk::frame .btns
ttk::button .btns.refresh -text "Refresh" -command refresh_window_list
ttk::button .btns.snap -text "Snap" -command do_snap
ttk::button .btns.arrange -text "Arrange" -command do_arrange
ttk::button .btns.launch -text "Launch" -command do_launch
ttk::button .btns.monitor -text "Monitor: ON" -command toggle_monitoring -style Monitor.On.TButton
ttk::label .btns.status -textvariable status -foreground gray -anchor w
ttk::button .btns.toggle -text "▶" -command toggle_card -width 2
pack .btns.refresh .btns.snap .btns.arrange .btns.launch .btns.monitor -side left -padx 3
pack .btns.toggle -side right -padx 3
pack .btns.status -side right -padx 10 -fill x -expand 1

# Collapsible card for window list
ttk::frame .card -relief groove -borderwidth 1

# Header row (inside card)
frame .hdr -background #e0e0e0
label .hdr.cb -text "" -width 3 -background #e0e0e0
label .hdr.role -text "Role" -width 16 -anchor w -background #e0e0e0 -font {TkDefaultFont 9 bold}
label .hdr.class -text "Class" -width 14 -anchor w -background #e0e0e0 -font {TkDefaultFont 9 bold}
label .hdr.geom -text "Geometry" -width 20 -anchor w -background #e0e0e0 -font {TkDefaultFont 9 bold}
label .hdr.cmd -text "Command" -width 30 -anchor w -background #e0e0e0 -font {TkDefaultFont 9 bold}
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

# Layout inside card
grid .hdr -in .card -row 0 -column 0 -columnspan 2 -sticky ew
grid .grid -in .card -row 1 -column 0 -sticky nsew
grid .vsb -in .card -row 1 -column 1 -sticky ns
grid columnconfigure .card 0 -weight 1
grid rowconfigure .card 1 -weight 1

# Main layout (card starts collapsed)
grid .btns -in .f -row 0 -column 0 -sticky ew -pady {0 5}
wm minsize . 600 0

grid columnconfigure .f 0 -weight 1
grid rowconfigure .f 1 -weight 1

# Keep window on top (optional - can be toggled)
# wm attributes . -topmost 1

# Initial setup
after idle {
    update idletasks

    # Position window
    set sw [winfo screenwidth .]
    wm geometry . 700x50+[expr {$sw - 750}]+50

    # Set _NET_WM_PID using TkX
    after 100 {
        set frame [wm frame .]
        if {$frame ne "0x0"} {
            catch {TkX::set_property [scan $frame %x] _NET_WM_PID [pid]}
        }
    }

    # Load window list
    refresh_window_list

    # Start monitoring loop (stateless - runs every 500ms)
    after 200 monitor_loop

    # Start focus highlight loop
    after 300 focus_highlight_loop
}
