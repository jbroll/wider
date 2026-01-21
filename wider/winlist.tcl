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

# Find best unclaimed slot matching role, returns {idx slot} or {-1 {}}
proc find_best_slot {role claimed_slots win} {
    set matching {}
    set idx -1
    foreach slot [slot::all] {
        incr idx
        if {$idx in $claimed_slots} continue
        if {![slot::has_role $slot $role]} continue
        lappend matching [list $idx $slot [slot::distance_to $win $slot]]
    }
    if {[llength $matching] == 0} {return {-1 {}}}
    set best [slot::min_by {apply {{x} {lindex $x 2}}} $matching]
    list [lindex $best 0] [lindex $best 1]
}

# Build slot dict with optional command
proc make_slot_dict {role class x y w h {cmd ""}} {
    set slot [dict create role $role class $class x $x y $y w $w h $h]
    if {$cmd ne ""} { dict set slot command $cmd }
    return $slot
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

    # Assign slots to windows (1:1 matching, closest first)
    set claimed {}
    set win_to_slot {}
    foreach win $wins {
        set role [dict get $win role]
        if {$role eq ""} continue
        lassign [find_best_slot $role $claimed $win] idx slot
        if {$idx >= 0} {
            lappend claimed $idx
            dict set win_to_slot [dict get $win id] $slot
        }
    }

    set row 0
    foreach win $wins {
        dict with win {
            set hints [win::get_size_hints $id]
            lassign [win::pixels_to_units $w $h $hints] uw uh
            set geom "${uw}x${uh}+${x}+${y}"

            set slot [win::dget $win_to_slot $id {}]
            set managed [expr {[dict size $slot] > 0}]
            set command [expr {$managed && [dict exists $slot command] ? [dict get $slot command] : [win::dget $win cmdline ""]}]

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
            set idx [slot::find_index $role $x $y]
            if {$idx >= 0} { slot::remove_at $idx }
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
            slot::add [make_slot_dict $role $class $x $y $w $h $command]
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

        set old_idx [slot::find_index $old_role $x $y]
        if {$old_idx >= 0} { slot::remove_at $old_idx }

        slot::add [make_slot_dict $new_role $class $x $y $w $h $command]
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

    if {$new_cmd ne ""} { win::set_command $id $new_cmd }
    dict set window_data $id command $new_cmd
    set status "Set WM_COMMAND: $new_cmd"
}

# ========== Actions ==========

proc save_all {} {
    global status window_data

    # Rebuild slot list from window_data
    set slot::data [lmap id_win [dict keys $window_data] {
        set win [dict get $window_data $id_win]
        if {![dict get $win managed]} continue
        dict with win {
            make_slot_dict $role $class $x $y $w $h $command
        }
    }]

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

            lassign [find_best_slot $role $claimed $win] idx slot

            if {$idx >= 0} {
                lappend claimed $idx
                dict set slot x $x
                dict set slot y $y
                dict set slot w $uw
                dict set slot h $uh
                if {$cmdline ne ""} { dict set slot command $cmdline }
                slot::set_at $idx $slot
            } else {
                slot::add [make_slot_dict $role $class $x $y $uw $uh $cmdline]
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
