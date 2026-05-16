# slots.tcl - Role/position configuration and window arrangement
#
# Data model:
#   slot::data is a dict: role_name -> {class CLASS command CMD positions {pos ...}}
#   Each position is a dict: {x X y Y w W h H}
#
# API:
#   slot::load / slot::save                - role configuration I/O
#   slot::all                              - get role dict
#   slot::positions                        - flat list of {role R class C command CMD x X y Y w W h H}
#   slot::add_position role pos ?class? ?command? - add position to role
#   slot::remove_position role idx         - remove position from role
#   slot::set_position role idx pos        - update position geometry
#   slot::set_command role cmd             - update role's command
#   slot::find_position role x y           - find position index by proximity
#   slot::find_window role                 - find window matching role
#   slot::distance_to win pos              - distance from window to position
#   slot::arrange_all                      - move windows to positions
#   slot::launch_all                       - launch missing apps
#   slot::generate_autostart               - create .desktop files
#   slot::generate_from_layout             - generate roles from layout

namespace eval slot {

    # ========== Functional Helpers ==========

    proc min_by {func list} {
        if {[llength $list] == 0} {return {}}
        set best [lindex $list 0]
        set best_val [{*}$func $best]
        foreach item [lrange $list 1 end] {
            set val [{*}$func $item]
            if {$val < $best_val} {
                set best $item
                set best_val $val
            }
        }
        return $best
    }

    proc group_by {func list} {
        set result {}
        foreach item $list {
            dict lappend result [{*}$func $item] $item
        }
        return $result
    }

    # ========== Slot State ==========

    variable file [file join $::env(HOME) .config wider slots.tcl]
    variable data {}

    # Return the role dict
    proc all {} { variable data; return $data }

    # Replace the entire role dict (used by Save to rebuild from live windows)
    proc replace_all {new} { variable data; set data $new }

    # Return flat list of position dicts with role/class/command merged in
    proc positions {} {
        variable data
        set result {}
        dict for {role_name role_info} $data {
            set cls [win::dget $role_info class ""]
            set cmd [win::dget $role_info command ""]
            foreach pos [dict get $role_info positions] {
                lappend result [dict merge $pos [dict create role $role_name class $cls command $cmd]]
            }
        }
        return $result
    }

    # ========== Slot I/O ==========

    proc load {{filename ""}} {
        variable file
        variable data
        if {$filename eq ""} { set filename $file }
        set filename [file normalize $filename]
        if {![file exists $filename]} { set data {}; return 0 }

        set interp [interp create -safe]
        set roles {}
        set old_slots {}

        # New format: role name { class ... command ... position ... }
        $interp alias role apply {{args} {
            upvar roles r
            if {[llength $args] == 2} {
                lassign $args name body
            } else {
                set name ""
                set body [lindex $args 0]
            }
            lappend r [list $name $body]
        }}

        # Old format: slot { role ... class ... geometry ... command ... }
        $interp alias slot apply {{args} {
            upvar old_slots sl
            lappend sl [lindex $args [expr {[llength $args] > 1 ? 1 : 0}]]
        }}

        try {
            $interp eval [read [set f [open $filename r]]]
            close $f
        } on error {msg} { catch {close $f}; interp delete $interp; error "error loading slots: $msg" }
        interp delete $interp

        if {[llength $roles] > 0} {
            # New format
            set data {}
            foreach entry $roles {
                lassign $entry name body
                set role_interp [interp create -safe]
                set pos_list {}
                set cls ""
                set cmd ""
                $role_interp alias position apply {{args} {
                    upvar pos_list pl
                    lappend pl [lindex $args 0]
                }}
                $role_interp alias class apply {{args} {
                    upvar cls c
                    set c [lindex $args 0]
                }}
                $role_interp alias command apply {{args} {
                    upvar cmd c
                    set c [lindex $args 0]
                }}
                $role_interp eval $body
                interp delete $role_interp

                set positions [lmap geom $pos_list { win::parse_geometry $geom }]
                set role_info [dict create positions $positions]
                if {$cls ne ""} { dict set role_info class $cls }
                if {$cmd ne ""} { dict set role_info command $cmd }
                dict set data $name $role_info
            }
        } elseif {[llength $old_slots] > 0} {
            # Old format - convert to role-centric
            set data {}
            foreach config $old_slots {
                set role_name [win::dget $config role ""]
                if {$role_name eq ""} continue
                set pos [win::parse_geometry [dict get $config geometry]]

                if {![dict exists $data $role_name]} {
                    set role_info [dict create positions [list $pos]]
                    if {[dict exists $config class]} { dict set role_info class [dict get $config class] }
                    if {[dict exists $config command]} {
                        # Strip stale --geometry= from command
                        set cmd [dict get $config command]
                        regsub { --geometry=[^ ]+} $cmd {} cmd
                        dict set role_info command $cmd
                    }
                    dict set data $role_name $role_info
                } else {
                    dict with data $role_name {
                        lappend positions $pos
                    }
                }
            }
        }

        # Return total position count
        set total 0
        dict for {_ info} $data { incr total [llength [dict get $info positions]] }
        return $total
    }

    proc save {{filename ""}} {
        variable file
        variable data
        if {$filename eq ""} { set filename $file }
        file mkdir [file dirname [set filename [file normalize $filename]]]

        set f [open $filename w]
        puts $f "# Slot configuration - [clock format [clock seconds]]\n"
        dict for {role_name role_info} $data {
            puts $f "role $role_name {"
            if {[dict exists $role_info class]} {
                puts $f "    class   [dict get $role_info class]"
            }
            if {[dict exists $role_info command]} {
                puts $f "    command {[dict get $role_info command]}"
            }
            foreach pos [dict get $role_info positions] {
                dict with pos {
                    puts $f "    position ${w}x${h}+${x}+${y}"
                }
            }
            puts $f "}\n"
        }
        close $f

        set total 0
        dict for {_ info} $data { incr total [llength [dict get $info positions]] }
        return $total
    }

    # ========== Role/Position Manipulation ==========

    proc add_position {role_name pos {cls ""} {cmd ""}} {
        variable data
        if {![dict exists $data $role_name]} {
            set role_info [dict create positions [list $pos]]
            if {$cls ne ""} { dict set role_info class $cls }
            if {$cmd ne ""} { dict set role_info command $cmd }
            dict set data $role_name $role_info
        } else {
            dict with data $role_name { lappend positions $pos }
        }
    }

    proc remove_position {role_name idx} {
        variable data
        if {![dict exists $data $role_name]} return
        dict with data $role_name {
            set positions [lreplace $positions $idx $idx]
        }
        # Remove role entirely if no positions left
        if {[llength [dict get [dict get $data $role_name] positions]] == 0} {
            dict unset data $role_name
        }
    }

    proc set_position {role_name idx pos} {
        variable data
        if {![dict exists $data $role_name]} return
        dict with data $role_name {
            lset positions $idx $pos
        }
    }

    proc set_command {role_name cmd} {
        variable data
        if {![dict exists $data $role_name]} return
        dict set data $role_name command $cmd
    }

    proc find_position {role_name x y {threshold 200}} {
        variable data
        if {![dict exists $data $role_name]} { return -1 }
        set idx -1
        foreach pos [dict get [dict get $data $role_name] positions] {
            incr idx
            if {abs($x - [dict get $pos x]) < $threshold && abs($y - [dict get $pos y]) < $threshold} {
                return $idx
            }
        }
        return -1
    }

    proc update_geometry {role_name old_x old_y new_x new_y new_w new_h} {
        variable data
        set idx [find_position $role_name $old_x $old_y]
        if {$idx < 0} { return 0 }
        set pos [dict create x $new_x y $new_y w $new_w h $new_h]
        set_position $role_name $idx $pos
        return 1
    }

    # ========== Window-Slot Matching ==========

    proc distance_to {win pos} {
        if {![dict exists $pos x]} {return 999999}
        expr {hypot([dict get $win x] - [dict get $pos x], [dict get $win y] - [dict get $pos y])}
    }

    proc find_window {role_name {cls ""} {exclude {}}} {
        set matches [lmap w [win::list] {
            if {[dict get $w id] in $exclude || [dict get $w role] ne $role_name} continue
            set w
        }]
        if {[llength $matches] > 0} { return $matches }
        if {$cls ne ""} {
            return [lmap w [win::list] {
                if {[dict get $w id] in $exclude || [dict get $w class] ne $cls} continue
                set w
            }]
        }
        return {}
    }

    # ========== Arrangement ==========

    proc arrange_all {} {
        variable data
        set count 0
        set assigned {}

        foreach slot [positions] {
            set role_name [dict get $slot role]
            set wins [find_window $role_name [dict get $slot class] $assigned]
            if {[llength $wins] == 0} continue

            set w [min_by [list apply {{slot win} {slot::distance_to $win $slot}} $slot] $wins]
            set id [dict get $w id]
            lappend assigned $id
            set hints [win::get_size_hints $id]
            lassign [win::units_to_pixels [dict get $slot w] [dict get $slot h] $hints] pw ph
            win::move $id [dict get $slot x] [dict get $slot y] $pw $ph
            incr count
        }
        return $count
    }

    proc launch_all {} {
        variable data
        set count 0

        dict for {role_name role_info} $data {
            if {![dict exists $role_info command]} continue
            set cmd [dict get $role_info command]
            set cls [win::dget $role_info class ""]
            set n_positions [llength [dict get $role_info positions]]
            set n_windows [llength [find_window $role_name $cls]]
            set n_launch [expr {$n_positions - $n_windows}]

            # Launch into unfilled positions (pick the ones with no nearby window)
            if {$n_launch > 0} {
                set wins [find_window $role_name $cls]
                foreach pos [dict get $role_info positions] {
                    if {$n_launch <= 0} break
                    # Check if any window is near this position
                    set filled 0
                    foreach w $wins {
                        if {[distance_to $w $pos] < 200} { set filled 1; break }
                    }
                    if {$filled} continue

                    dict with pos {
                        set geom "${w}x${h}+${x}+${y}"
                    }
                    set exec_cmd $cmd
                    if {[string match "*--geometry=*" $exec_cmd]} {
                        regsub {--geometry=[^ ]+} $exec_cmd "--geometry=$geom" exec_cmd
                    } elseif {[dict exists $role_info class] && [dict get $role_info class] in {Xfce4-terminal}} {
                        append exec_cmd " --geometry=$geom"
                    }
                    exec {*}$exec_cmd &
                    incr count
                    incr n_launch -1
                }
            }
        }
        return $count
    }

    # ========== Autostart Generation ==========

    variable autostart_dir [file join $::env(HOME) .config autostart]

    proc generate_autostart {{dirname ""}} {
        variable autostart_dir
        variable data
        if {$dirname eq ""} { set dirname $autostart_dir }
        file mkdir $dirname

        foreach f [glob -nocomplain -directory $dirname wider-*.desktop] { file delete $f }

        set count 0
        dict for {role_name role_info} $data {
            if {![dict exists $role_info command]} continue
            set cmd [dict get $role_info command]
            set cls [win::dget $role_info class ""]
            set pos_idx 0

            foreach pos [dict get $role_info positions] {
                incr pos_idx
                incr count
                dict with pos {
                    set geom "${w}x${h}+${x}+${y}"
                }
                set exec_cmd $cmd
                if {![string match "*--role=*" $exec_cmd]} { append exec_cmd " --role=$role_name" }
                if {[string match "*--geometry=*" $exec_cmd]} {
                    regsub {--geometry=[^ ]+} $exec_cmd "--geometry=$geom" exec_cmd
                } elseif {$cls in {Xfce4-terminal}} {
                    append exec_cmd " --geometry=$geom"
                }

                set f [open [file join $dirname wider-${role_name}-${pos_idx}.desktop] w]
                puts $f "\[Desktop Entry\]\nType=Application\nName=${role_name}-${pos_idx}\nExec=$exec_cmd\nX-GNOME-Autostart-enabled=true"
                close $f
            }
        }
        return $count
    }

    # ========== Legacy Layout Support ==========

    variable layout_file [file join $::env(HOME) .config wider layout.tcl]

    proc save_layout {{filename ""}} {
        variable layout_file
        if {$filename eq ""} { set filename $layout_file }
        file mkdir [file dirname [set filename [file normalize $filename]]]

        set layout [lmap w [win::list] {
            if {[dict get $w desktop] == -1} continue
            set w
        }]

        set f [open $filename w]
        puts $f "# Window layout saved [clock format [clock seconds]]"
        puts $f "set layout {"
        foreach w $layout { puts $f "    {$w}" }
        puts $f "}"
        close $f
        llength $layout
    }

    proc restore_layout {{filename ""}} {
        variable layout_file
        if {$filename eq ""} { set filename $layout_file }
        set filename [file normalize $filename]
        if {![file exists $filename]} { error "layout file not found: $filename" }

        source $filename
        set used {}
        set restored 0

        foreach win [win::list] {
            dict with win {
                set best_idx -1
                set best_diff 999999999
                for {set i 0} {$i < [llength $layout]} {incr i} {
                    if {$i in $used} continue
                    set saved [lindex $layout $i]
                    if {[dict get $saved class] ne $class} continue
                    set diff [expr {abs($w - [dict get $saved w]) + abs($h - [dict get $saved h])}]
                    if {$diff < $best_diff} { set best_diff $diff; set best_idx $i }
                }
                if {$best_idx >= 0} {
                    lappend used $best_idx
                    set saved [lindex $layout $best_idx]
                    win::move $id [dict get $saved desktop] [dict get $saved x] [dict get $saved y]
                    incr restored
                }
            }
        }
        return $restored
    }

    proc generate_from_layout {{layout_filename ""} {slots_filename ""}} {
        variable layout_file
        variable file
        variable data

        if {$layout_filename eq ""} { set layout_filename $layout_file }
        if {$slots_filename eq ""} { set slots_filename $file }
        if {![file exists $layout_filename]} { error "layout file not found: $layout_filename" }

        source $layout_filename

        # Group windows by class
        set by_class [group_by {apply {{win} { dict get $win class }}} $layout]

        set data {}
        dict for {cls wins} $by_class {
            set base_role [string tolower [dict get [lindex $wins 0] instance]]
            set role_info [dict create class $cls positions {}]
            set cmdline [dict get [lindex $wins 0] cmdline]
            if {$cmdline ne ""} { dict set role_info command $cmdline }

            foreach w $wins {
                dict with role_info {
                    lappend positions [dict create \
                        x [dict get $w x] y [dict get $w y] \
                        w [dict get $w w] h [dict get $w h]]
                }
            }
            dict set data $base_role $role_info
        }

        save $slots_filename
        set total 0
        dict for {_ info} $data { incr total [llength [dict get $info positions]] }
        return $total
    }
}
