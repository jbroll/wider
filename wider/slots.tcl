# slots.tcl - Slot configuration and window arrangement
#
# API:
#   slot::load / slot::save             - slot configuration I/O
#   slot::all                           - get all slots
#   slot::add / slot::set / slot::remove - slot manipulation
#   slot::find_index                    - find slot by role and position
#   slot::find_window                   - find window matching slot
#   slot::distance_to                   - distance from window to slot
#   slot::arrange_all                   - move windows to slots
#   slot::launch_all                    - launch missing apps
#   slot::generate_autostart            - create .desktop files
#   slot::generate_from_layout          - generate slots from layout

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

    proc has_role {slot role} {
        expr {[dict exists $slot role] && [dict get $slot role] eq $role}
    }

    # ========== Slot State ==========

    variable file [file join $::env(HOME) .config wider slots.tcl]
    variable data {}

    proc all {} { variable data; return $data }

    # ========== Slot I/O ==========

    proc load {{filename ""}} {
        variable file
        variable data
        if {$filename eq ""} { set filename $file }
        set filename [file normalize $filename]
        if {![file exists $filename]} { set data {}; return 0 }

        set interp [interp create -safe]
        set slot_list {}
        $interp alias slot apply {{args} {
            upvar slot_list sl
            lappend sl [lindex $args [expr {[llength $args] > 1 ? 1 : 0}]]
        }}

        try {
            $interp eval [read [set f [open $filename r]]]
            close $f
        } on error {msg} { catch {close $f}; interp delete $interp; error "error loading slots: $msg" }
        interp delete $interp

        set data [lmap config $slot_list {
            if {[dict exists $config geometry]} {
                set config [dict merge $config [win::parse_geometry [dict get $config geometry]]]
                dict unset config geometry
            }
            set config
        }]
        llength $data
    }

    proc save {{filename ""}} {
        variable file
        variable data
        if {$filename eq ""} { set filename $file }
        file mkdir [file dirname [set filename [file normalize $filename]]]

        set f [open $filename w]
        puts $f "# Slot configuration - [clock format [clock seconds]]\n"
        foreach slot $data {
            dict with slot {
                puts $f "slot {"
                if {[info exists role]} { puts $f "    role     $role" }
                if {[info exists class]} { puts $f "    class    $class" }
                if {[info exists x] && [info exists w]} { puts $f "    geometry ${w}x${h}+${x}+${y}" }
                if {[info exists command]} { puts $f "    command  {$command}" }
                puts $f "}\n"
            }
        }
        close $f
        llength $data
    }

    # ========== Slot Manipulation ==========

    proc add {slot} { variable data; lappend data $slot }
    proc set_at {idx slot} { variable data; lset data $idx $slot }
    proc remove_at {idx} { variable data; set data [lreplace $data $idx $idx] }

    proc find_index {role x y {threshold 200}} {
        variable data
        set idx -1
        foreach slot $data {
            incr idx
            if {![has_role $slot $role]} continue
            if {abs($x - [dict get $slot x]) < $threshold && abs($y - [dict get $slot y]) < $threshold} {
                return $idx
            }
        }
        return -1
    }

    proc update_geometry {role old_x old_y new_x new_y new_w new_h} {
        variable data
        set idx [find_index $role $old_x $old_y]
        if {$idx < 0} { return 0 }
        set slot [lindex $data $idx]
        dict set slot x $new_x; dict set slot y $new_y
        dict set slot w $new_w; dict set slot h $new_h
        lset data $idx $slot
        return 1
    }

    # ========== Window-Slot Matching ==========

    proc distance_to {win slot} {
        if {![dict exists $slot x]} {return 999999}
        expr {hypot([dict get $win x] - [dict get $slot x], [dict get $win y] - [dict get $slot y])}
    }

    proc find_window {slot {exclude {}}} {
        set slot_role [dict get $slot role]
        set matches [lmap w [win::list] {
            if {[dict get $w id] in $exclude || [dict get $w role] ne $slot_role} continue
            set w
        }]
        if {[llength $matches] > 0} {
            return [min_by [list apply {{slot win} {slot::distance_to $win $slot}} $slot] $matches]
        }
        set slot_class [win::dget $slot class]
        if {$slot_class ne ""} {
            foreach w [win::list] {
                if {[dict get $w id] ni $exclude && [dict get $w class] eq $slot_class} { return $w }
            }
        }
        return ""
    }

    # ========== Arrangement ==========

    proc arrange_all {} {
        variable data
        set count 0
        set assigned {}

        foreach slot $data {
            set w [find_window $slot $assigned]
            if {$w eq ""} continue
            set id [dict get $w id]
            lappend assigned $id
            dict with slot {
                if {[info exists x]} {
                    set hints [win::get_size_hints $id]
                    lassign [win::units_to_pixels $w $h $hints] pw ph
                    win::move $id $x $y $pw $ph
                }
            }
            incr count
        }
        return $count
    }

    proc launch_all {} {
        variable data
        set count 0
        foreach slot $data {
            if {[find_window $slot] ne ""} continue
            dict with slot {
                if {![info exists command]} continue
                set cmd [string map [list {$role} $role {$geometry} "${w}x${h}+${x}+${y}"] $command]
            }
            exec {*}$cmd &
            incr count
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
        set idx 0
        foreach slot $data {
            incr idx
            dict with slot {
                if {![info exists command]} continue
                set geom "${w}x${h}+${x}+${y}"
                set exec_cmd [string map [list {$role} $role {$geometry} $geom] $command]
                if {![string match "*--role=*" $exec_cmd]} { append exec_cmd " --role=$role" }
                set cls [expr {[info exists class] ? $class : ""}]
                if {$cls in {Xfce4-terminal} && ![string match "*--geometry=*" $exec_cmd]} {
                    append exec_cmd " --geometry=$geom"
                }

                set f [open [file join $dirname wider-$idx.desktop] w]
                puts $f "\[Desktop Entry\]\nType=Application\nName=$role\nExec=$exec_cmd\nX-GNOME-Autostart-enabled=true"
                close $f
                incr count
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

        set geom_groups [group_by {apply {{win} {
            format "%s:%dx%d" [dict get $win class] [dict get $win w] [dict get $win h]
        }}} $layout]

        set data {}
        dict for {key wins} $geom_groups {
            regexp {^([^:]+):(\d+)x(\d+)$} $key -> cls ww hh
            set base_role [string tolower [dict get [lindex $wins 0] instance]]
            set group_size [llength $wins]

            foreach w $wins {
                dict with w {
                    set role [expr {$group_size > 1 ? "${base_role}-${ww}x${hh}" : $base_role}]
                    set config [dict create role $role class $cls x $x y $y w $ww h $hh]
                    if {$cmdline ne ""} {
                        dict set config command [expr {$group_size > 1 && $cls eq "Xfce4-terminal" ? "$cmdline --role=$role" : $cmdline}]
                    }
                    lappend data $config
                }
            }
        }

        save $slots_filename
        llength $data
    }
}
