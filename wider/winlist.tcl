# winlist.tcl - Window list UI and handlers
#
# Manages the scrollable window list, event handlers for editing slots,
# and action buttons (refresh, snap, arrange, launch).

# Window list state
set window_data {}
set row_widgets {}

# Skip classes for window filtering
set skip_classes {Xfdesktop Xfce4-panel Plank Polybar Xfwm4 Wrapper-2.0}

# ========== Helper Procs ==========

# Find best unclaimed position for a role, returns {role_name pos_idx pos} or {"" -1 {}}
proc find_best_position {role claimed win} {
    set role_data [slot::all]
    if {![dict exists $role_data $role]} {return {"" -1 {}}}
    set role_info [dict get $role_data $role]
    set positions [dict get $role_info positions]

    set matching {}
    set idx -1
    foreach pos $positions {
        incr idx
        set key "$role:$idx"
        if {$key in $claimed} continue
        lappend matching [list $role $idx $pos [slot::distance_to $win $pos]]
    }
    if {[llength $matching] == 0} {return {"" -1 {}}}
    set best [slot::min_by {apply {{x} {lindex $x 3}}} $matching]
    list [lindex $best 0] [lindex $best 1] [lindex $best 2]
}

# Create entry widget with Return/FocusOut bindings
proc make_entry {parent name width value handler} {
    set w $parent.$name
    entry $w -width $width
    $w insert 0 $value
    bind $w <Return> $handler
    bind $w <FocusOut> $handler
    return $w
}

# Get change context for event handler, returns {} if no change needed
proc get_change_context {id field} {
    global window_data row_widgets
    if {![dict exists $window_data $id]} {return {}}
    set widgets [dict get $row_widgets $id]
    set entry [dict get $widgets $field]
    set new_val [string trim [$entry get]]
    set win [dict get $window_data $id]
    set old_val [dict get $win $field]
    if {$new_val eq $old_val} {return {}}
    list $entry $new_val $win $old_val $widgets
}

# Filter predicate for displayable windows
proc displayable_window? {win} {
    global skip_classes
    expr {[dict get $win class] ni $skip_classes && [dict get $win desktop] ne "-1"}
}

# Normalize hex window ID (strip leading zeros after 0x)
proc normalize_id {id} {
    if {[string match "0x*" $id]} {format "0x%x" [scan $id "%x"]} else {set id}
}

# ========== Focus Highlight ==========

proc update_focus_highlight {} {
    global row_widgets
    set focused [normalize_id [TkX::active_window]]

    dict for {id widgets} $row_widgets {
        set bg [expr {[normalize_id $id] eq $focused ? "#cce5ff" : "#ffffff"}]
        catch {
            foreach w {frame class title} {
                [dict get $widgets $w] configure -background $bg
            }
        }
    }
}

proc focus_highlight_loop {} {
    catch {update_focus_highlight}
    after 250 focus_highlight_loop
}

# ========== Window List ==========

proc refresh_window_list {} {
    global status window_data row_widgets

    foreach child [winfo children .card.list.canvas.inner] { destroy $child }
    set window_data {}
    set row_widgets {}

    # Filter and sort windows (empty roles last)
    set wins [lsort -command {apply {{a b} {
        set ra [dict get $a role]
        set rb [dict get $b role]
        if {$ra eq "" && $rb eq ""} {return 0}
        if {$ra eq ""} {return 1}
        if {$rb eq ""} {return -1}
        string compare $ra $rb
    }}} [pick displayable_window? [win::list]]]

    # Assign positions to windows (1:1 matching, closest first)
    set claimed {}
    set win_to_pos {}
    foreach win $wins {
        set role [dict get $win role]
        if {$role eq ""} continue
        lassign [find_best_position $role $claimed $win] r idx pos
        if {$idx >= 0} {
            lappend claimed "$r:$idx"
            dict set win_to_pos [dict get $win id] [dict create role $r pos_idx $idx pos $pos]
        }
    }

    set row 0
    foreach win $wins {
        dict with win {
            set hints [win::get_size_hints $id]
            lassign [win::pixels_to_units $w $h $hints] uw uh
            set geom "${uw}x${uh}+${x}+${y}"

            set match [win::dget $win_to_pos $id {}]
            set managed [expr {[dict size $match] > 0}]

            # Get command from role config if managed, else from window
            set command ""
            if {$managed} {
                set role_data [slot::all]
                set r [dict get $match role]
                if {[dict exists $role_data $r] && [dict exists [dict get $role_data $r] command]} {
                    set command [dict get [dict get $role_data $r] command]
                }
            }
            if {$command eq ""} { set command [win::dget $win cmdline ""] }

            dict set window_data $id [dict create \
                class $class role $role geom $geom title $title \
                x $x y $y w $uw h $uh managed $managed command $command]

            # Create row
            set rf .card.list.canvas.inner.r$row
            frame $rf -background white
            grid $rf -row $row -column 0 -sticky ew

            set var "::managed_$id"
            set $var $managed
            checkbutton $rf.cb -variable $var -command [list on_managed_toggle $id] \
                -background white -activebackground white

            make_entry $rf role 16 $role [list on_role_change $id]
            label $rf.class -text $class -width 14 -anchor w -background white
            make_entry $rf geom 20 $geom [list on_geom_change $id]
            make_entry $rf cmd 30 $command [list on_command_change $id]

            set short_title [string range $title 0 25]
            if {[string length $title] > 25} { append short_title "..." }
            label $rf.title -text $short_title -anchor w -background white

            grid $rf.cb $rf.role $rf.class $rf.geom $rf.cmd $rf.title -sticky w -padx 2 -pady 1
            grid columnconfigure $rf 5 -weight 1

            dict set row_widgets $id [dict create \
                frame $rf cb $rf.cb role $rf.role class $rf.class \
                geom $rf.geom cmd $rf.cmd title $rf.title var $var]
        }
        incr row
    }

    update idletasks
    .card.list.canvas configure -scrollregion [.card.list.canvas bbox all]
    set status "Refreshed $row windows"
}

# ========== Event Handlers ==========

proc on_managed_toggle {id} {
    global window_data status row_widgets

    if {![dict exists $window_data $id]} return
    set widgets [dict get $row_widgets $id]
    set managed [set [dict get $widgets var]]
    set win [dict get $window_data $id]

    dict with win {
        if {!$managed} {
            set idx [slot::find_position $role $x $y]
            if {$idx >= 0} { slot::remove_position $role $idx }
            dict set window_data $id managed 0
            set status "Removed $class from slots"
        } else {
            if {$role eq ""} {
                set role [string tolower $class]
                win::set_role $id $role
                dict set window_data $id role $role
                [dict get $widgets role] delete 0 end
                [dict get $widgets role] insert 0 $role
            }
            set pos [dict create x $x y $y w $w h $h]
            slot::add_position $role $pos $class $command
            dict set window_data $id managed 1
            set status "Added $class to slots"
        }
    }
    save_all
}

proc on_role_change {id} {
    global window_data status

    set ctx [get_change_context $id role]
    if {$ctx eq {}} return
    lassign $ctx entry new_role win old_role widgets

    if {$new_role eq ""} return

    dict with win {
        win::set_role $id $new_role
        dict set window_data $id role $new_role

        # Remove from old role
        set old_idx [slot::find_position $old_role $x $y]
        if {$old_idx >= 0} { slot::remove_position $old_role $old_idx }

        # Add to new role
        set pos [dict create x $x y $y w $w h $h]
        slot::add_position $new_role $pos $class $command
    }

    dict set window_data $id managed 1
    set [dict get $widgets var] 1
    set status "Role: $new_role"
    save_all
}

proc on_geom_change {id} {
    global window_data status

    set ctx [get_change_context $id geom]
    if {$ctx eq {}} return
    lassign $ctx entry new_geom win old_geom

    if {[catch {win::parse_geometry $new_geom} parsed]} {
        set status "Invalid geometry: $new_geom"
        $entry delete 0 end
        $entry insert 0 $old_geom
        return
    }

    dict with parsed {
        set hints [win::get_size_hints $id]
        lassign [win::units_to_pixels $w $h $hints] pw ph
        win::move $id $x $y $pw $ph

        if {[slot::update_geometry [dict get $win role] [dict get $win x] [dict get $win y] $x $y $w $h]} {
            save_all
        }

        dict set window_data $id x $x
        dict set window_data $id y $y
        dict set window_data $id w $w
        dict set window_data $id h $h
        dict set window_data $id geom $new_geom
    }
    set status "Geometry: $new_geom"
}

proc on_command_change {id} {
    global window_data status row_widgets

    if {![dict exists $window_data $id]} return
    set widgets [dict get $row_widgets $id]
    set entry [dict get $widgets cmd]
    set new_cmd [string trim [$entry get]]
    set old_cmd [dict get [dict get $window_data $id] command]
    if {$new_cmd eq $old_cmd} return

    set win [dict get $window_data $id]
    set role [dict get $win role]

    if {$new_cmd ne ""} { win::set_command $id $new_cmd }
    dict set window_data $id command $new_cmd

    # Update the role's command (affects all positions of this role)
    if {$role ne ""} {
        slot::set_command $role $new_cmd
        save_all
    }
    set status "Command for $role: $new_cmd"
}

# ========== Actions ==========

proc save_all {} {
    global status window_data

    # Update slot data from window_data, preserving unoccupied positions
    # Group managed windows by role
    set by_role {}
    dict for {id win} $window_data {
        if {![dict get $win managed]} continue
        set role [dict get $win role]
        dict lappend by_role $role $win
    }

    # For each role with managed windows, update class/command and positions
    set role_data [slot::all]
    set new_data {}

    # First, preserve existing roles (keeps unoccupied positions)
    dict for {role_name role_info} $role_data {
        dict set new_data $role_name $role_info
    }

    # Update roles that have managed windows
    dict for {role wins} $by_role {
        set first [lindex $wins 0]
        set positions [lmap w $wins {
            dict create x [dict get $w x] y [dict get $w y] \
                        w [dict get $w w] h [dict get $w h]
        }]

        if {[dict exists $new_data $role]} {
            # Role exists - update positions for windows we know about,
            # but keep positions that have no current window
            set existing [dict get [dict get $new_data $role] positions]
            set updated_positions {}
            set used_wins {}

            # Match existing positions to windows
            foreach epos $existing {
                set best_win ""
                set best_dist 999999
                foreach w $wins {
                    set wid [dict get $w role];# just for tracking
                    if {$w in $used_wins} continue
                    set d [slot::distance_to $w $epos]
                    if {$d < $best_dist} { set best_dist $d; set best_win $w }
                }
                if {$best_win ne "" && $best_dist < 400} {
                    # Update position from window
                    lappend updated_positions [dict create \
                        x [dict get $best_win x] y [dict get $best_win y] \
                        w [dict get $best_win w] h [dict get $best_win h]]
                    lappend used_wins $best_win
                } else {
                    # Keep existing position (no matching window)
                    lappend updated_positions $epos
                }
            }
            # Add any windows that didn't match an existing position
            foreach w $wins {
                if {$w in $used_wins} continue
                lappend updated_positions [dict create \
                    x [dict get $w x] y [dict get $w y] \
                    w [dict get $w w] h [dict get $w h]]
            }
            dict set new_data $role positions $updated_positions
            dict set new_data $role class [dict get $first class]
            if {[dict get $first command] ne ""} {
                dict set new_data $role command [dict get $first command]
            }
        } else {
            # New role
            set role_info [dict create \
                class [dict get $first class] \
                positions $positions]
            if {[dict get $first command] ne ""} {
                dict set role_info command [dict get $first command]
            }
            dict set new_data $role $role_info
        }
    }

    set slot::data $new_data
    slot::save
    slot::generate_autostart
    set status "Saved slots and autostart files"
}

proc do_arrange {} {
    global status
    focus .
    update
    try {
        set count [slot::arrange_all]
        set status "Arranged $count windows"
        refresh_window_list
    } on error {msg} {
        set status "Error: $msg"
    }
}

proc do_launch {} {
    global status
    focus .
    update
    try {
        set count [slot::launch_all]
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

proc do_snap {} {
    global status monitoring

    # Force FocusOut on any active entry to apply pending edits
    focus .
    update

    set was_monitoring $monitoring
    set monitoring 0
    set count 0
    set claimed {}

    foreach win [win::list] {
        set role [dict get $win role]
        if {$role eq ""} continue

        dict with win {
            set hints [win::get_size_hints $id]
            lassign [win::pixels_to_units $w $h $hints] uw uh

            lassign [find_best_position $role $claimed $win] r idx pos

            set new_pos [dict create x $x y $y w $uw h $uh]
            if {$idx >= 0} {
                lappend claimed "$r:$idx"
                slot::set_position $role $idx $new_pos
            } else {
                slot::add_position $role $new_pos $class
            }
        }
        incr count
    }

    if {$count > 0} {
        slot::save
        slot::generate_autostart
        set status "Snapped $count windows"
        refresh_window_list
    } else {
        set status "No windows to snap"
    }

    set monitoring $was_monitoring
}
