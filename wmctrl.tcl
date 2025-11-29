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

    # Get command line for a process from /proc
    # Returns empty string if PID is 0 or not accessible
    proc get_cmdline {pid} {
        if {$pid == 0} {return ""}
        set path "/proc/$pid/cmdline"
        if {![file exists $path]} {return ""}
        try {
            set f [open $path r]
            set data [read $f]
            close $f
            # cmdline is null-separated, convert to space-separated
            return [string trimright [string map {\x00 " "} $data]]
        } on error {} {
            return ""
        }
    }

    # List all windows managed by the window manager
    # Returns list of dicts with keys:
    #   id desktop pid x y w h instance class host title cmdline
    # Uses xdotool for geometry (consistent across HiDPI), wmctrl for metadata
    proc windows {} {
        set result {}
        set output [exec wmctrl -l -x -p]
        foreach line [split $output \n] {
            set parts [regexp -inline -all {\S+} $line]
            if {[llength $parts] < 5} continue

            lassign $parts id desktop pid class host
            set title [join [lrange $parts 5 end] " "]

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

            # Get geometry from xdotool (consistent across HiDPI)
            set geom [exec xdotool getwindowgeometry $id]
            regexp {Position: (\d+),(\d+)} $geom -> x y
            regexp {Geometry: (\d+)x(\d+)} $geom -> w h

            # Get command line from /proc
            set cmdline [get_cmdline $pid]

            lappend result [dict create \
                id $id \
                desktop $desktop \
                pid $pid \
                x $x y $y w $w h $h \
                instance $instance \
                class $classname \
                host $host \
                title $title \
                cmdline $cmdline]
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

    # Calculate move offset for a window
    # GTK windows (parent is root): no offset
    # CSD windows (has _MOTIF_WM_HINTS): relative offset only
    # SSD windows (server-side decorations): relative + frame_top
    proc get_move_offset {id} {
        # Check if parent is root (GTK/CSD with composited decorations)
        set tree [exec xwininfo -id $id -tree]
        regexp {Parent window id: (0x[0-9a-f]+)} $tree -> parent
        set root_info [exec xwininfo -root]
        regexp {Window id: (0x[0-9a-f]+)} $root_info -> root_id

        if {$parent eq $root_id} {
            return {0 0}
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
            return [list $rel_x $rel_y]
        }

        # SSD - add frame_top from _NET_FRAME_EXTENTS
        set frame_top 0
        try {
            set extents [exec xprop -id $id _NET_FRAME_EXTENTS]
            regexp {(\d+),\s*(\d+),\s*(\d+),\s*(\d+)} $extents -> l r t b
            set frame_top $t
        } on error {} {}

        return [list $rel_x [expr {$rel_y + $frame_top}]]
    }

    # Move and optionally resize a window
    # Uses xdotool for positioning with offset compensation
    # Uses wmctrl for desktop switching
    # Forms:
    #   wm::move id x y                 - move only
    #   wm::move id desktop x y         - move to desktop and position
    #   wm::move id x y w h             - move and resize
    #   wm::move id desktop x y w h     - move to desktop, position and resize
    proc move {id args} {
        lassign [get_move_offset $id] off_x off_y

        switch [llength $args] {
            2 {
                lassign $args x y
                exec xdotool windowmove $id [expr {$x - $off_x}] [expr {$y - $off_y}]
            }
            3 {
                lassign $args desktop x y
                exec wmctrl -i -r $id -t $desktop
                exec xdotool windowmove $id [expr {$x - $off_x}] [expr {$y - $off_y}]
            }
            4 {
                lassign $args x y w h
                exec xdotool windowmove $id [expr {$x - $off_x}] [expr {$y - $off_y}]
                exec xdotool windowsize $id $w $h
            }
            5 {
                lassign $args desktop x y w h
                exec wmctrl -i -r $id -t $desktop
                exec xdotool windowmove $id [expr {$x - $off_x}] [expr {$y - $off_y}]
                exec xdotool windowsize $id $w $h
            }
            default {
                error "usage: wm::move id ?desktop? x y ?w h?"
            }
        }
    }

    # Default layout file
    variable layout_file [file join $::env(HOME) .config wider layout.tcl]

    # Save current window layout to file
    # Saves: class, instance, desktop, x, y, w, h for each window
    proc save {{filename ""}} {
        variable layout_file
        if {$filename eq ""} {
            set filename $layout_file
        }
        set filename [file normalize $filename]

        # Ensure directory exists
        file mkdir [file dirname $filename]

        # Collect window data
        set layout {}
        foreach win [windows] {
            set wclass [dict get $win class]
            set winstance [dict get $win instance]
            set wdesktop [dict get $win desktop]

            # Skip desktop icons and panels (desktop -1 = sticky)
            if {$wdesktop == -1} continue
            # Skip ourselves
            if {$winstance eq "wider" || $wclass eq "Wider.tcl"} continue

            lappend layout [dict create \
                class $wclass \
                instance $winstance \
                desktop $wdesktop \
                x [dict get $win x] \
                y [dict get $win y] \
                w [dict get $win w] \
                h [dict get $win h]]
        }

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

            # Skip ourselves
            if {$instance eq "wider" || $class eq "Wider.tcl"} continue

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
}
