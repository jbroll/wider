# wmctrl.tcl - Tcl interface to wmctrl
#
# API:
#   wm::windows                           - list all windows
#   wm::windows_quick                     - fast position-only list
#   wm::state id add|remove|toggle prop...  - change window state
#   wm::move id ?desktop? x y ?w h?       - move/resize window
#   wm::xprop id                          - list all properties
#   wm::xprop id prop                     - get property value
#   wm::xprop id prop value               - set property value
#   wm::save ?filename?                   - save window layout
#   wm::restore ?filename?                - restore window layout
#   wm::get_role id                       - get WM_WINDOW_ROLE
#   wm::set_role id role                  - set WM_WINDOW_ROLE
#   wm::parse_geometry geom               - parse X11 geometry string
#   wm::load_slots ?filename?             - load slot configuration
#   wm::find_window_for_slot slot         - find window matching slot
#   wm::find_slot_for_window id           - find slot for window
#   wm::slot_distance win slot            - distance from window to slot center
#   wm::arrange_slot slot                 - move window to slot position
#   wm::arrange_all                       - arrange all windows to slots
#   wm::swap_slots slot1 slot2            - swap windows between slots

namespace eval wm {

    # Require TkX for fast Xlib-based window queries
    package require TkX

    # Get/set X window properties via xprop
    # Forms:
    #   wm::xprop id              - list all properties (as dict)
    #   wm::xprop id prop         - get single property value
    #   wm::xprop id prop value   - set property value
    proc xprop {id args} {
        switch [llength $args] {
            0 {
                # List all properties as dict
                set result {}
                set output [exec xprop -id $id]
                foreach line [split $output \n] {
                    if {[regexp {^([^(]+)\([^)]+\)\s*=\s*(.*)$} $line -> name value]} {
                        set name [string trim $name]
                        dict set result $name $value
                    }
                }
                return $result
            }
            1 {
                # Get single property
                set prop [lindex $args 0]
                try {
                    set output [exec xprop -id $id $prop]
                    # Output format: PROP_NAME(TYPE) = value
                    if {[regexp {\)\s*=\s*(.*)$} $output -> value]} {
                        return [string trim $value]
                    }
                } on error {} {}
                return ""
            }
            2 {
                # Set property using TkX
                lassign $args prop value
                TkX::set_property [scan $id %x] $prop $value
            }
            default {
                error "usage: wm::xprop id ?prop? ?value?"
            }
        }
    }

    # Get WM_WINDOW_ROLE property
    proc get_role {id} {
        set val [xprop $id WM_WINDOW_ROLE]
        if {[regexp {^"([^"]*)"} $val -> role]} {
            return $role
        }
        return ""
    }

    # Set WM_WINDOW_ROLE property using TkX (no exec)
    proc set_role {id role} {
        TkX::set_property [scan $id %x] WM_WINDOW_ROLE $role
    }

    # Set WM_COMMAND property (ICCCM session management)
    proc set_command {id cmd} {
        TkX::set_property [scan $id %x] WM_COMMAND $cmd
    }

    # Parse X11 geometry string (WxH+X+Y or WxH-X-Y)
    # Returns dict with keys: w h x y
    proc parse_geometry {geom {screenw 0} {screenh 0}} {
        if {$screenw == 0} {
            catch {set screenw [winfo screenwidth .]}
            if {$screenw == 0} {set screenw 1920}
        }
        if {$screenh == 0} {
            catch {set screenh [winfo screenheight .]}
            if {$screenh == 0} {set screenh 1080}
        }
        # Handle WxH+X+Y, WxH-X-Y, and WxH+-X+-Y (negative coordinates)
        if {[regexp {^(\d+)x(\d+)([+-])(-?\d+)([+-])(-?\d+)$} $geom -> w h xs x ys y]} {
            if {$xs eq "-" && $x >= 0} { set x [expr {$screenw - $x - $w}] }
            if {$ys eq "-" && $y >= 0} { set y [expr {$screenh - $y - $h}] }
            return [dict create w $w h $h x $x y $y]
        }
        error "invalid geometry: $geom"
    }

    # Get command line for a window
    # Checks WM_COMMAND (ICCCM) first, falls back to /proc/pid/cmdline
    proc get_cmdline {id} {
        # Check ICCCM WM_COMMAND property
        set wm_cmd [xprop $id WM_COMMAND]
        if {$wm_cmd ne ""} {
            # WM_COMMAND format: { "arg0", "arg1", ... } - parse it
            if {[regexp {\{(.+)\}} $wm_cmd -> args]} {
                set cmdlist {}
                foreach {full capture} [regexp -all -inline {"([^"]*)"} $args] {
                    lappend cmdlist $capture
                }
                if {[llength $cmdlist] > 0} {
                    return [join $cmdlist " "]
                }
            }
        }
        # Fall back to /proc cmdline via _NET_WM_PID
        set pid [xprop $id _NET_WM_PID]
        if {![string is integer -strict $pid] || $pid == 0} {return ""}
        set path "/proc/$pid/cmdline"
        if {![file exists $path]} {return ""}
        try {
            set f [open $path r]
            set data [read $f]
            close $f
            return [string trimright [string map {\x00 " "} $data]]
        } on error {} {
            return ""
        }
    }

    # Fast window list - positions only via TkX (direct Xlib)
    # For monitoring loop where we just need id, x, y, w, h
    proc windows_quick {} {
        return [TkX::list_windows]
    }

    # List all windows managed by the window manager
    # Returns list of dicts with keys:
    #   id x y w h class role pid cmdline
    proc windows {} {
        set result {}
        foreach win [TkX::list_windows] {
            set id [dict get $win id]
            set props [TkX::get_props [scan $id %x]]

            # Merge window geometry with properties
            dict set win role [dict get $props role]
            dict set win pid [dict get $props pid]

            # Convert command list to string
            set cmd [dict get $props command]
            if {[llength $cmd] > 0} {
                dict set win cmdline [join $cmd " "]
            } else {
                # Fallback to /proc for cmdline
                set pid [dict get $props pid]
                if {$pid != 0} {
                    set path "/proc/$pid/cmdline"
                    if {[file exists $path]} {
                        catch {
                            set f [open $path r]
                            set data [read $f]
                            close $f
                            dict set win cmdline [string trimright [string map {\x00 " "} $data]]
                        }
                    }
                }
                if {![dict exists $win cmdline]} {
                    dict set win cmdline ""
                }
            }

            lappend result $win
        }
        return $result
    }

    # Change window state using TkX (no exec)
    # action: add, remove, or toggle
    # props: one or more of: modal, sticky, maximized_vert, maximized_horz,
    #        shaded, skip_taskbar, skip_pager, hidden, fullscreen, above, below
    proc state {id action args} {
        if {[llength $args] == 0} {
            error "usage: wm::state id add|remove|toggle prop ?prop?"
        }
        set winId [scan $id %x]
        set prop1 "_NET_WM_STATE_[string toupper [lindex $args 0]]"
        set prop2 ""
        if {[llength $args] > 1} {
            set prop2 "_NET_WM_STATE_[string toupper [lindex $args 1]]"
        }
        TkX::window_state $winId $action $prop1 $prop2
    }

    # Move and optionally resize a window using TkX (no exec)
    # Forms:
    #   wm::move id x y                 - move only
    #   wm::move id desktop x y         - move to desktop and position
    #   wm::move id x y w h             - move and resize
    #   wm::move id desktop x y w h     - move to desktop, position and resize
    proc move {id args} {
        set winId [scan $id %x]
        switch [llength $args] {
            2 {
                lassign $args x y
                TkX::move_window $winId $x $y -1 -1
            }
            3 {
                lassign $args desktop x y
                TkX::set_desktop $winId $desktop
                TkX::move_window $winId $x $y -1 -1
            }
            4 {
                lassign $args x y w h
                TkX::move_window $winId $x $y $w $h
            }
            5 {
                lassign $args desktop x y w h
                TkX::set_desktop $winId $desktop
                TkX::move_window $winId $x $y $w $h
            }
            default {
                error "usage: wm::move id ?desktop? x y ?w h?"
            }
        }
    }

    # Default layout file
    variable layout_file [file join $::env(HOME) .config wider layout.tcl]

    # Save current window layout to file
    proc save {{filename ""}} {
        variable layout_file
        if {$filename eq ""} {
            set filename $layout_file
        }
        set filename [file normalize $filename]

        # Ensure directory exists
        file mkdir [file dirname $filename]

        # Filter out sticky windows (desktop -1 = panels, desktop icons)
        set layout [lmap win [windows] {
            if {[dict get $win desktop] == -1} continue
            set win
        }]

        # Write to file
        set f [open $filename w]
        puts $f "# Window layout saved [clock format [clock seconds]]"
        puts $f "set layout {"
        foreach win $layout {
            puts $f "    {$win}"
        }
        puts $f "}"
        close $f

        return [llength $layout]
    }

    # Restore window layout from file
    # Matches by class and closest size
    proc restore {{filename ""}} {
        variable layout_file
        if {$filename eq ""} {
            set filename $layout_file
        }
        set filename [file normalize $filename]

        if {![file exists $filename]} {
            error "layout file not found: $filename"
        }

        # Load saved layout
        source $filename

        # Get current windows
        set current [windows]

        # Track which saved entries have been used
        set used {}
        set restored 0

        foreach win $current {
            set id [dict get $win id]
            set class [dict get $win class]
            set instance [dict get $win instance]
            set w [dict get $win w]
            set h [dict get $win h]

            # Find best match: same class, closest size
            set best_idx -1
            set best_diff 999999999

            for {set i 0} {$i < [llength $layout]} {incr i} {
                if {$i in $used} continue

                set saved [lindex $layout $i]
                if {[dict get $saved class] ne $class} continue

                # Calculate size difference
                set sw [dict get $saved w]
                set sh [dict get $saved h]
                set diff [expr {abs($w - $sw) + abs($h - $sh)}]

                if {$diff < $best_diff} {
                    set best_diff $diff
                    set best_idx $i
                }
            }

            # Apply if match found
            if {$best_idx >= 0} {
                set saved [lindex $layout $best_idx]
                lappend used $best_idx

                set sx [dict get $saved x]
                set sy [dict get $saved y]
                set sd [dict get $saved desktop]

                # Move window to saved position
                move $id $sd $sx $sy
                incr restored
            }
        }

        return $restored
    }

    # ========== Slot Management ==========

    # Slot configuration file
    variable slots_file [file join $::env(HOME) .config wider slots.tcl]

    # Loaded slots (list of slot dicts)
    # Each slot: {role <role> class <class> x <x> y <y> w <w> h <h> ?command <cmd>?}
    variable slots {}

    # Load slot configuration from file
    proc load_slots {{filename ""}} {
        variable slots_file
        variable slots

        if {$filename eq ""} {
            set filename $slots_file
        }
        set filename [file normalize $filename]

        if {![file exists $filename]} {
            set slots {}
            return 0
        }

        # Create safe interpreter for parsing
        set interp [interp create -safe]

        # Define 'slot' command that captures slot definitions
        # Supports both old format (slot name {...}) and new format (slot {...})
        set slot_list {}
        $interp alias slot apply {{args} {
            upvar slot_list sl
            if {[llength $args] == 1} {
                # New format: slot {config dict}
                lappend sl [lindex $args 0]
            } else {
                # Old format: slot name {config dict} - ignore name
                lappend sl [lindex $args 1]
            }
        }}

        # Source the config file
        try {
            $interp eval [read [set f [open $filename r]]]
            close $f
        } on error {msg} {
            catch {close $f}
            interp delete $interp
            error "error loading slots: $msg"
        }
        interp delete $interp

        # Process loaded slots
        set slots {}
        foreach config $slot_list {
            # Parse geometry if present
            if {[dict exists $config geometry]} {
                set geom [parse_geometry [dict get $config geometry]]
                dict set config x [dict get $geom x]
                dict set config y [dict get $geom y]
                dict set config w [dict get $geom w]
                dict set config h [dict get $geom h]
                dict unset config geometry
            }
            lappend slots $config
        }

        return [llength $slots]
    }

    # Save current slot configuration to file
    proc save_slots {{filename ""}} {
        variable slots_file
        variable slots

        if {$filename eq ""} {
            set filename $slots_file
        }
        set filename [file normalize $filename]

        file mkdir [file dirname $filename]

        set f [open $filename w]
        puts $f "# Slot configuration - [clock format [clock seconds]]"
        puts $f ""

        foreach slot $slots {
            puts $f "slot {"
            if {[dict exists $slot role]} {
                puts $f "    role     [dict get $slot role]"
            }
            if {[dict exists $slot class]} {
                puts $f "    class    [dict get $slot class]"
            }
            if {[dict exists $slot x] && [dict exists $slot w]} {
                set x [dict get $slot x]
                set y [dict get $slot y]
                set w [dict get $slot w]
                set h [dict get $slot h]
                puts $f "    geometry ${w}x${h}+${x}+${y}"
            }
            if {[dict exists $slot command]} {
                puts $f "    command  {[dict get $slot command]}"
            }
            puts $f "}"
            puts $f ""
        }
        close $f

        return [llength $slots]
    }

    # Add a slot to the list
    proc add_slot {slot} {
        variable slots
        lappend slots $slot
    }

    # Remove slots matching a predicate (proc that takes slot, returns true to remove)
    proc remove_slots {predicate} {
        variable slots
        set new_slots {}
        foreach slot $slots {
            if {![{*}$predicate $slot]} {
                lappend new_slots $slot
            }
        }
        set slots $new_slots
    }

    # Update a slot's geometry by matching role and old position
    proc update_slot_geometry {role old_x old_y new_x new_y new_w new_h} {
        variable slots
        set idx [find_slot_index $role $old_x $old_y]
        if {$idx < 0} {
            return 0
        }
        set slot [lindex $slots $idx]
        dict set slot x $new_x
        dict set slot y $new_y
        dict set slot w $new_w
        dict set slot h $new_h
        lset slots $idx $slot
        return 1
    }

    # Find window matching a slot by role (or class fallback)
    # When multiple windows share a role, picks the one closest to slot geometry
    # Optional exclude list: window IDs to skip (already assigned to other slots)
    # Returns window dict or empty string
    proc find_window_for_slot {slot {exclude {}}} {
        set slot_role [dict get $slot role]
        set slot_class [expr {[dict exists $slot class] ? [dict get $slot class] : ""}]

        # Collect all windows matching the role (excluding already-assigned)
        set matches {}
        foreach win [windows] {
            set id [dict get $win id]
            if {$id in $exclude} continue
            set win_role [dict get $win role]
            if {$win_role ne "" && $win_role eq $slot_role} {
                lappend matches $win
            }
        }

        # If multiple matches, pick closest to slot geometry
        if {[llength $matches] > 1} {
            set best ""
            set best_dist 999999
            foreach win $matches {
                set dist [slot_distance_to $win $slot]
                if {$dist < $best_dist} {
                    set best_dist $dist
                    set best $win
                }
            }
            return $best
        } elseif {[llength $matches] == 1} {
            return [lindex $matches 0]
        }

        # Fallback: match by class (for singleton apps, excluding already-assigned)
        if {$slot_class ne ""} {
            foreach win [windows] {
                set id [dict get $win id]
                if {$id in $exclude} continue
                if {[dict get $win class] eq $slot_class} {
                    return $win
                }
            }
        }

        return ""
    }

    # Find slot for a window by ID (closest matching slot)
    # Returns slot dict or empty dict
    proc find_slot_for_window {id} {
        variable slots
        foreach win [windows] {
            if {[dict get $win id] eq $id} {
                set matching [find_slots_for_window $win]
                if {[llength $matching] > 0} {
                    return [pick_closest_slot $win $matching]
                }
                return {}
            }
        }
        return {}
    }

    # Find slots matching a window (by role or class)
    # Returns list of matching slot dicts
    proc find_slots_for_window {win_data} {
        variable slots
        set win_role [dict get $win_data role]
        set win_class [dict get $win_data class]

        set matches {}
        foreach slot $slots {
            if {$win_role ne "" && [dict exists $slot role] && [dict get $slot role] eq $win_role} {
                lappend matches $slot
            } elseif {$win_class ne "" && [dict exists $slot class] && [dict get $slot class] eq $win_class} {
                lappend matches $slot
            }
        }
        return $matches
    }

    # Find slot index by matching role and position
    proc find_slot_index {role x y {threshold 200}} {
        variable slots
        set idx -1
        foreach slot $slots {
            incr idx
            if {![dict exists $slot role] || [dict get $slot role] ne $role} continue
            set sx [dict get $slot x]
            set sy [dict get $slot y]
            if {abs($x - $sx) < $threshold && abs($y - $sy) < $threshold} {
                return $idx
            }
        }
        return -1
    }

    # Update slot at index
    proc set_slot {idx slot} {
        variable slots
        lset slots $idx $slot
    }

    # Remove slot at index
    proc remove_slot_at {idx} {
        variable slots
        set slots [lreplace $slots $idx $idx]
    }

    # Calculate distance from window to slot (center to center)
    # Distance from window position to slot position (corner to corner)
    proc slot_distance_to {win slot} {
        if {![dict exists $slot x]} {
            return 999999
        }

        set wx [dict get $win x]
        set wy [dict get $win y]
        set sx [dict get $slot x]
        set sy [dict get $slot y]

        # Euclidean distance between top-left corners
        return [expr {sqrt(($wx - $sx)**2 + ($wy - $sy)**2)}]
    }

    # Helper: pick slot closest to window from list of slots
    proc pick_closest_slot {win slot_list} {
        set best {}
        set best_dist 999999
        foreach slot $slot_list {
            set dist [slot_distance_to $win $slot]
            if {$dist < $best_dist} {
                set best_dist $dist
                set best $slot
            }
        }
        return $best
    }

    # Move window to a slot position
    proc arrange_slot {slot} {
        set win [find_window_for_slot $slot]
        if {$win eq ""} {
            return 0
        }

        dict with slot {
            if {![info exists x]} {
                return 0
            }
            move [dict get $win id] $x $y $w $h
        }
        return 1
    }

    # Arrange all windows to their slot positions
    # Windows already at their slot position are not moved
    # Ensures one window per slot
    proc arrange_all {} {
        variable slots
        set count 0
        set assigned_slots {}   ;# list of slot indices already assigned
        set assigned_windows {} ;# list of window IDs already assigned
        set in_position_threshold 50

        # First pass: snap windows near their slot to exact position
        set idx -1
        foreach slot $slots {
            incr idx
            set win [find_window_for_slot $slot $assigned_windows]
            if {$win eq ""} continue

            set id [dict get $win id]
            set dist [slot_distance_to $win $slot]

            if {$dist < $in_position_threshold} {
                lappend assigned_slots $idx
                lappend assigned_windows $id
                # Only move if not already at exact position
                if {$dist > 0} {
                    dict with slot {
                        if {[info exists x]} {
                            move $id $x $y $w $h
                        }
                    }
                    incr count
                }
            }
        }

        # Second pass: move remaining windows to remaining slots
        set idx -1
        foreach slot $slots {
            incr idx
            if {$idx in $assigned_slots} continue

            set win [find_window_for_slot $slot $assigned_windows]
            if {$win eq ""} continue

            set id [dict get $win id]
            lappend assigned_slots $idx
            lappend assigned_windows $id

            dict with slot {
                if {[info exists x]} {
                    move $id $x $y $w $h
                }
            }
            incr count
        }
        return $count
    }

    # Swap windows between two slots
    # Takes slot dicts and window IDs
    proc swap_slots {slot1 slot2 id1 id2} {
        dict with slot1 {
            set x1 $x; set y1 $y; set w1 $w; set h1 $h
        }
        dict with slot2 {
            set x2 $x; set y2 $y; set w2 $w; set h2 $h
        }
        move $id1 $x2 $y2 $w2 $h2
        move $id2 $x1 $y1 $w1 $h1
        return 1
    }

    # Launch app for a slot (if not already running)
    proc launch_slot {slot} {
        # Check if window already exists
        if {[find_window_for_slot $slot] ne ""} {
            return 0
        }

        dict with slot {
            if {![info exists command]} {
                return 0
            }
            set geom "${w}x${h}+${x}+${y}"
            set cmd [string map [list {$role} $role {$geometry} $geom] $command]
        }
        exec {*}$cmd &
        return 1
    }

    # Launch all missing apps from slots
    proc launch_all {} {
        variable slots
        set count 0
        foreach slot $slots {
            incr count [launch_slot $slot]
        }
        return $count
    }

    # Autostart directory
    variable autostart_dir [file join $::env(HOME) .config autostart]

    # Generate autostart .desktop files from slots
    # Files are named wider-{idx}.desktop
    proc generate_autostart {{dirname ""}} {
        variable autostart_dir
        variable slots

        if {$dirname eq ""} {
            set dirname $autostart_dir
        }
        file mkdir $dirname

        # Remove old wider-managed autostart files
        foreach f [glob -nocomplain -directory $dirname wider-*.desktop] {
            file delete $f
        }

        set count 0
        set idx 0
        foreach slot $slots {
            incr idx
            dict with slot {
                if {![info exists command]} continue

                set geom "${w}x${h}+${x}+${y}"
                set cmd [string map [list {$role} $role {$geometry} $geom] $command]
                set cls [expr {[info exists class] ? $class : ""}]

                # Build exec command with role
                set exec $cmd
                if {![string match "*--role=*" $exec]} {
                    append exec " --role=$role"
                }
                if {$cls in {Xfce4-terminal} && ![string match "*--geometry=*" $exec]} {
                    append exec " --geometry=$geom"
                }

                # Write .desktop file
                set filename [file join $dirname wider-$idx.desktop]
                set f [open $filename w]
                puts $f "\[Desktop Entry\]"
                puts $f "Type=Application"
                puts $f "Name=$role (Wider)"
                puts $f "Exec=$exec"
                puts $f "X-GNOME-Autostart-enabled=true"
                close $f

                incr count
            }
        }

        return $count
    }

    # Generate slots from saved layout file
    # Windows with same class and similar geometry share a role (swappable)
    proc generate_slots {{layout_filename ""} {slots_filename ""}} {
        variable layout_file
        variable slots_file
        variable slots

        if {$layout_filename eq ""} {
            set layout_filename $layout_file
        }
        if {$slots_filename eq ""} {
            set slots_filename $slots_file
        }

        if {![file exists $layout_filename]} {
            error "layout file not found: $layout_filename"
        }

        # Load layout
        source $layout_filename

        # Group windows by class+geometry (w x h) for shared roles
        set geom_groups {}
        foreach win $layout {
            dict with win {
                if {$class eq "Wider.tcl"} continue
                set key "$class:${w}x${h}"
                dict lappend geom_groups $key $win
            }
        }

        # Generate slots - windows in same geom group share a role
        set slots {}

        dict for {key wins} $geom_groups {
            regexp {^([^:]+):(\d+)x(\d+)$} $key -> cls ww hh

            set instance [dict get [lindex $wins 0] instance]
            set base_role [string tolower $instance]
            set group_size [llength $wins]

            foreach win $wins {
                dict with win {
                    if {$group_size > 1} {
                        set role "${base_role}-${ww}x${hh}"
                    } else {
                        set role $base_role
                    }

                    set config [dict create \
                        role $role \
                        class $cls \
                        x $x y $y w $ww h $hh]

                    if {$cmdline ne ""} {
                        if {$group_size > 1 && $cls eq "Xfce4-terminal"} {
                            dict set config command "$cmdline --role=$role"
                        } else {
                            dict set config command $cmdline
                        }
                    }

                    lappend slots $config
                }
            }
        }

        save_slots $slots_filename
        return [llength $slots]
    }
}
