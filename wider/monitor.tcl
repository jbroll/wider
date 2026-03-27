# monitor.tcl - Window position monitoring subsystem
#
# Monitors window positions and snaps them to slots when they get close.
# Handles swap detection when two windows with the same role approach the same slot.

# Monitoring state
set monitoring 1
set monitor_interval 500  ;# ms
set swap_threshold 150    ;# pixels - distance to trigger swap
set pending_snap ""
set pending_geom {}

# Sort comparator: left-to-right, top-to-bottom
proc slot_position_cmp {a b} {
    set cmp [expr {[dict get $a x] - [dict get $b x]}]
    if {$cmp != 0} {return $cmp}
    expr {[dict get $a y] - [dict get $b y]}
}

proc assign_and_snap_slots {} {
    global status swap_threshold pending_snap pending_geom

    set windows [win::list]
    set active_id [TkX::active_window]

    # Group windows by role (skip empty roles)
    set by_role [slot::group_by {apply {{win} {dict get $win role}}} \
        [lmap win $windows {
            if {[dict get $win role] eq ""} continue
            set win
        }]]

    set sorted_slots [lsort -command slot_position_cmp [slot::positions]]
    set assigned {}
    set unassigned {}
    set empty_slots {}

    foreach slot $sorted_slots {
        set role [dict get $slot role]
        set sx [dict get $slot x]
        set sy [dict get $slot y]

        # Get candidates (same role, not yet assigned) with distances
        set candidates {}
        if {[dict exists $by_role $role]} {
            foreach win [dict get $by_role $role] {
                set id [dict get $win id]
                if {$id ni $assigned} {
                    set wx [dict get $win x]
                    set wy [dict get $win y]
                    set dist [expr {$wx == $sx && $wy == $sy ? 0 : [slot::distance_to $win $slot]}]
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
            # Window exactly in slot - check for swap
            if {[llength $candidates] > 1} {
                lassign [lindex $candidates 1] second_id second_dist second_win
                if {$second_dist <= $swap_threshold} {
                    lappend assigned $second_id
                    lappend unassigned [list $first_id $first_win]
                    # Move second window into slot, or defer if dragged
                    set hints [win::get_size_hints $second_id]
                    lassign [win::units_to_pixels [dict get $slot w] [dict get $slot h] $hints] pw ph
                    if {$second_id ne $active_id} {
                        win::move $second_id 0 $sx $sy $pw $ph
                    } else {
                        set pending_snap $second_id
                        set pending_geom [list $sx $sy $pw $ph]
                    }
                    set status "Swapped"
                    continue
                }
            }
            lappend assigned $first_id
        } elseif {$first_dist <= $swap_threshold} {
            lappend assigned $first_id
            if {$first_id ne $active_id} {
                set hints [win::get_size_hints $first_id]
                lassign [win::units_to_pixels [dict get $slot w] [dict get $slot h] $hints] pw ph
                win::move $first_id 0 $sx $sy $pw $ph
            }
        } else {
            lappend empty_slots $slot
        }
    }

    # Place displaced windows in empty slots (find closest matching role)
    foreach entry $unassigned {
        if {[llength $empty_slots] == 0} break
        lassign $entry win_id win_data
        set win_role [dict get $win_data role]

        # Filter to matching roles and find closest
        set matching [lmap slot $empty_slots {
            if {[dict get $slot role] ne $win_role} continue
            set slot
        }]
        if {[llength $matching] == 0} continue

        set best_slot [slot::min_by [list apply {{win slot} {slot::distance_to $win $slot}} $win_data] $matching]
        set empty_slots [lsearch -all -inline -not -exact $empty_slots $best_slot]

        if {$win_id ne $active_id} {
            dict with best_slot {
                set hints [win::get_size_hints $win_id]
                lassign [win::units_to_pixels $w $h $hints] pw ph
                win::move $win_id 0 $x $y $pw $ph
            }
        }
    }

    # Complete pending snap when mouse released
    if {$pending_snap ne ""} {
        set pstate [TkX::pointer_state]
        if {![dict get $pstate button1] && ![dict get $pstate button2] && ![dict get $pstate button3]} {
            lassign $pending_geom x y w h
            win::move $pending_snap 0 $x $y $w $h
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
