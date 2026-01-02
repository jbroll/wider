# wmctrl.tcl - Tcl interface to wmctrl
#
# API:
#   wm::windows                           - list all windows
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
                # Set property
                lassign $args prop value
                # Determine type - default to UTF8_STRING
                exec xprop -id $id -f $prop 8u -set $prop $value
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

    # Set WM_WINDOW_ROLE property
    proc set_role {id role} {
        exec xprop -id $id -f WM_WINDOW_ROLE 8s -set WM_WINDOW_ROLE $role
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
        if {[regexp {^(\d+)x(\d+)([+-])(\d+)([+-])(\d+)$} $geom -> w h xs x ys y]} {
            if {$xs eq "-"} { set x [expr {$screenw - $x - $w}] }
            if {$ys eq "-"} { set y [expr {$screenh - $y - $h}] }
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

    # List all windows managed by the window manager
    # Returns list of dicts with keys:
    #   id desktop pid x y w h instance class host title cmdline
    proc windows {} {
        set result {}
        set output [exec wmctrl -l -x -G -p]
        foreach line [split $output \n] {
            set parts [regexp -inline -all {\S+} $line]
            if {[llength $parts] < 9} continue

            lassign $parts id desktop pid x y w h class host
            set title [join [lrange $parts 9 end] " "]

            # Split class into instance.class
            set instance ""
            set classname $class
            if {[regexp {^([^.]+)\.(.+)$} $class -> instance classname]} {
                # matched
            }

            # Fallback to xprop if wmctrl didn't get the PID
            if {$pid == 0} {
                set xpid [xprop $id _NET_WM_PID]
                if {[string is integer -strict $xpid]} {
                    set pid $xpid
                }
            }

            # Get command line (WM_COMMAND or /proc fallback)
            set cmdline [get_cmdline $id]

            # Get WM_WINDOW_ROLE
            set role [get_role $id]

            lappend result [dict create \
                id $id \
                desktop $desktop \
                pid $pid \
                x $x y $y w $w h $h \
                instance $instance \
                class $classname \
                host $host \
                title $title \
                cmdline $cmdline \
                role $role]
        }
        return $result
    }

    # Change window state
    # action: add, remove, or toggle
    # props: one or more of: modal, sticky, maximized_vert, maximized_horz,
    #        shaded, skip_taskbar, skip_pager, hidden, fullscreen, above, below
    proc state {id action args} {
        if {[llength $args] == 0} {
            error "usage: wm::state id add|remove|toggle prop ?prop?"
        }
        exec wmctrl -i -r $id -b $action,[join $args ,]
    }

    # Determine window type and move offset
    # Returns: {type off_x off_y}
    # Types: gtk (needs /2), csd (relative offset), ssd (relative + frame_top)
    proc get_window_type {id} {
        # Check if parent is root (GTK window)
        set tree [exec xwininfo -id $id -tree]
        regexp {Parent window id: (0x[0-9a-f]+)} $tree -> parent
        set root_info [exec xwininfo -root]
        regexp {Window id: (0x[0-9a-f]+)} $root_info -> root_id

        if {$parent eq $root_id} {
            return {gtk 0 0}
        }

        # Get relative offset from xwininfo
        set xwin [exec xwininfo -id $id]
        set rel_x 0
        set rel_y 0
        regexp {Relative upper-left X:\s*(\d+)} $xwin -> rel_x
        regexp {Relative upper-left Y:\s*(\d+)} $xwin -> rel_y

        # Check for CSD (_MOTIF_WM_HINTS present)
        set has_csd 0
        try {
            set motif [exec xprop -id $id _MOTIF_WM_HINTS]
            if {![string match "*not found*" $motif]} {
                set has_csd 1
            }
        } on error {} {}

        if {$has_csd} {
            return [list csd $rel_x $rel_y]
        }

        # SSD - add frame extents from _NET_FRAME_EXTENTS
        set frame_left 0
        set frame_top 0
        try {
            set extents [exec xprop -id $id _NET_FRAME_EXTENTS]
            regexp {(\d+),\s*(\d+),\s*(\d+),\s*(\d+)} $extents -> l r t b
            set frame_left $l
            set frame_top $t
        } on error {} {}

        return [list ssd [expr {$rel_x + $frame_left}] [expr {$rel_y + $frame_top}]]
    }

    # Move and optionally resize a window
    # Uses wmctrl with offset compensation based on window type
    # Forms:
    #   wm::move id x y                 - move only
    #   wm::move id desktop x y         - move to desktop and position
    #   wm::move id x y w h             - move and resize
    #   wm::move id desktop x y w h     - move to desktop, position and resize
    proc move {id args} {
        lassign [get_window_type $id] type off_x off_y

        # Calculate wmctrl coordinates
        switch [llength $args] {
            2 {
                lassign $args x y
                if {$type eq "gtk"} {
                    set wx [expr {$x / 2}]
                    set wy [expr {$y / 2}]
                } else {
                    set wx [expr {$x - $off_x}]
                    set wy [expr {$y - $off_y}]
                }
                exec wmctrl -i -r $id -e 0,$wx,$wy,-1,-1
            }
            3 {
                lassign $args desktop x y
                if {$type eq "gtk"} {
                    set wx [expr {$x / 2}]
                    set wy [expr {$y / 2}]
                } else {
                    set wx [expr {$x - $off_x}]
                    set wy [expr {$y - $off_y}]
                }
                exec wmctrl -i -r $id -t $desktop
                exec wmctrl -i -r $id -e 0,$wx,$wy,-1,-1
            }
            4 {
                lassign $args x y w h
                if {$type eq "gtk"} {
                    set wx [expr {$x / 2}]
                    set wy [expr {$y / 2}]
                    set ww [expr {$w / 2}]
                    set wh [expr {$h / 2}]
                } else {
                    set wx [expr {$x - $off_x}]
                    set wy [expr {$y - $off_y}]
                    set ww $w
                    set wh $h
                }
                exec wmctrl -i -r $id -e 0,$wx,$wy,$ww,$wh
            }
            5 {
                lassign $args desktop x y w h
                if {$type eq "gtk"} {
                    set wx [expr {$x / 2}]
                    set wy [expr {$y / 2}]
                    set ww [expr {$w / 2}]
                    set wh [expr {$h / 2}]
                } else {
                    set wx [expr {$x - $off_x}]
                    set wy [expr {$y - $off_y}]
                    set ww $w
                    set wh $h
                }
                exec wmctrl -i -r $id -t $desktop
                exec wmctrl -i -r $id -e 0,$wx,$wy,$ww,$wh
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

    # Loaded slots (dict: name -> slot config)
    variable slots {}

    # Load slot configuration from file
    # File format uses 'slot' command to define each slot
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
        set slot_list {}
        $interp alias slot apply {{name config} {
            upvar slot_list sl
            lappend sl $name $config
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
        foreach {name config} $slot_list {
            # Parse geometry if present
            if {[dict exists $config geometry]} {
                set geom [parse_geometry [dict get $config geometry]]
                dict set config x [dict get $geom x]
                dict set config y [dict get $geom y]
                dict set config w [dict get $geom w]
                dict set config h [dict get $geom h]
            }
            dict set slots $name $config
        }

        return [dict size $slots]
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

        dict for {name config} $slots {
            puts $f "slot $name {"
            if {[dict exists $config role]} {
                puts $f "    role     [dict get $config role]"
            }
            if {[dict exists $config class]} {
                puts $f "    class    [dict get $config class]"
            }
            # Write geometry in X11 format
            if {[dict exists $config x] && [dict exists $config w]} {
                set x [dict get $config x]
                set y [dict get $config y]
                set w [dict get $config w]
                set h [dict get $config h]
                puts $f "    geometry ${w}x${h}+${x}+${y}"
            }
            if {[dict exists $config command]} {
                puts $f "    command  {[dict get $config command]}"
            }
            puts $f "}"
            puts $f ""
        }
        close $f

        return [dict size $slots]
    }

    # Find window matching a slot by role (or class fallback)
    # Returns window dict or empty string
    proc find_window_for_slot {slot_name} {
        variable slots
        if {![dict exists $slots $slot_name]} {
            return ""
        }
        set slot [dict get $slots $slot_name]
        set slot_role [dict get $slot role]
        set slot_class [expr {[dict exists $slot class] ? [dict get $slot class] : ""}]

        foreach win [windows] {
            set win_role [dict get $win role]
            set win_class [dict get $win class]

            # Match by role first
            if {$win_role ne "" && $win_role eq $slot_role} {
                return $win
            }
        }

        # Fallback: match by class (for singleton apps)
        if {$slot_class ne ""} {
            foreach win [windows] {
                if {[dict get $win class] eq $slot_class} {
                    return $win
                }
            }
        }

        return ""
    }

    # Find which slot a window belongs to (by role or class)
    # Returns slot name or empty string
    proc find_slot_for_window {id} {
        variable slots

        # Get window info
        set win_role [get_role $id]

        # First try to match by role
        if {$win_role ne ""} {
            dict for {name config} $slots {
                if {[dict exists $config role] && [dict get $config role] eq $win_role} {
                    return $name
                }
            }
        }

        # Fallback: match by class
        set props [xprop $id]
        set win_class ""
        if {[dict exists $props WM_CLASS]} {
            # WM_CLASS format: "instance", "class"
            regexp {"[^"]*",\s*"([^"]*)"} [dict get $props WM_CLASS] -> win_class
        }

        if {$win_class ne ""} {
            dict for {name config} $slots {
                if {[dict exists $config class] && [dict get $config class] eq $win_class} {
                    return $name
                }
            }
        }

        return ""
    }

    # Calculate distance from window center to slot center
    proc slot_distance {win slot_name} {
        variable slots
        if {![dict exists $slots $slot_name]} {
            return 999999
        }
        set slot [dict get $slots $slot_name]

        # Window center
        set wx [expr {[dict get $win x] + [dict get $win w] / 2}]
        set wy [expr {[dict get $win y] + [dict get $win h] / 2}]

        # Slot center
        set sx [expr {[dict get $slot x] + [dict get $slot w] / 2}]
        set sy [expr {[dict get $slot y] + [dict get $slot h] / 2}]

        # Euclidean distance
        return [expr {sqrt(($wx - $sx)**2 + ($wy - $sy)**2)}]
    }

    # Move window to its slot position
    proc arrange_slot {slot_name} {
        variable slots
        if {![dict exists $slots $slot_name]} {
            return 0
        }

        set win [find_window_for_slot $slot_name]
        if {$win eq ""} {
            return 0
        }

        set slot [dict get $slots $slot_name]
        set id [dict get $win id]
        set x [dict get $slot x]
        set y [dict get $slot y]
        set w [dict get $slot w]
        set h [dict get $slot h]

        move $id $x $y $w $h
        return 1
    }

    # Arrange all windows to their slot positions
    proc arrange_all {} {
        variable slots
        set count 0
        dict for {name config} $slots {
            incr count [arrange_slot $name]
        }
        return $count
    }

    # Swap windows between two slots
    proc swap_slots {slot1 slot2} {
        variable slots
        if {![dict exists $slots $slot1] || ![dict exists $slots $slot2]} {
            return 0
        }

        set win1 [find_window_for_slot $slot1]
        set win2 [find_window_for_slot $slot2]

        if {$win1 eq "" || $win2 eq ""} {
            return 0
        }

        set s1 [dict get $slots $slot1]
        set s2 [dict get $slots $slot2]

        # Swap roles
        set id1 [dict get $win1 id]
        set id2 [dict get $win2 id]
        set role1 [dict get $s1 role]
        set role2 [dict get $s2 role]

        set_role $id1 $role2
        set_role $id2 $role1

        # Move to swapped positions
        move $id1 [dict get $s2 x] [dict get $s2 y] [dict get $s2 w] [dict get $s2 h]
        move $id2 [dict get $s1 x] [dict get $s1 y] [dict get $s1 w] [dict get $s1 h]

        return 1
    }

    # Launch app for a slot (if not already running)
    proc launch_slot {slot_name} {
        variable slots
        if {![dict exists $slots $slot_name]} {
            return 0
        }

        # Check if window already exists
        if {[find_window_for_slot $slot_name] ne ""} {
            return 0
        }

        set slot [dict get $slots $slot_name]
        if {![dict exists $slot command]} {
            return 0
        }

        set cmd [dict get $slot command]
        exec {*}$cmd &
        return 1
    }

    # Launch all missing apps from slots
    proc launch_all {} {
        variable slots
        set count 0
        dict for {name config} $slots {
            incr count [launch_slot $name]
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
        # Key: "class:WxH" -> list of windows
        set geom_groups {}
        foreach win $layout {
            set class [dict get $win class]
            if {$class eq "Wider.tcl"} continue
            set w [dict get $win w]
            set h [dict get $win h]
            set key "$class:${w}x${h}"
            dict lappend geom_groups $key $win
        }

        # Generate slots - windows in same geom group share a role
        set slots {}
        set role_idx {}  ;# track index within each role group

        dict for {key wins} $geom_groups {
            regexp {^([^:]+):(\d+)x(\d+)$} $key -> class w h

            # Determine base role name
            set instance [dict get [lindex $wins 0] instance]
            set base_role [string tolower $instance]

            # If multiple windows share this geometry, they're swappable
            set group_size [llength $wins]
            set idx 0

            foreach win $wins {
                incr idx
                set x [dict get $win x]
                set y [dict get $win y]
                set cmdline [dict get $win cmdline]

                if {$group_size > 1} {
                    # Shared role for swappable windows
                    set role "${base_role}-${w}x${h}"
                    set slot_name "${base_role}-${w}x${h}-$idx"
                } else {
                    # Singleton
                    set role $base_role
                    set slot_name $base_role
                }

                # Build slot config
                set config [dict create \
                    role $role \
                    class $class \
                    x $x y $y w $w h $h]

                # Add command if available
                if {$cmdline ne ""} {
                    if {$group_size > 1 && $class eq "Xfce4-terminal"} {
                        dict set config command "$cmdline --role=$role"
                    } else {
                        dict set config command $cmdline
                    }
                }

                dict set slots $slot_name $config
            }
        }

        # Save generated slots
        save_slots $slots_filename
        return [dict size $slots]
    }
}
