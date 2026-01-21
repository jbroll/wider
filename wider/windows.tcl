# windows.tcl - Window operations using TkX
#
# API:
#   win::list                             - list all windows with properties
#   win::move id ?desktop? x y ?w h?      - move/resize window
#   win::state id add|remove|toggle prop  - change window state
#   win::set_role id role                 - set WM_WINDOW_ROLE
#   win::set_command id cmd               - set WM_COMMAND
#   win::get_size_hints id                - get WM_NORMAL_HINTS
#   win::pixels_to_units / units_to_pixels - size conversion for terminals
#   win::parse_geometry geom              - parse X11 geometry string

namespace eval win {

    package require TkX

    proc dget {d key {default ""}} {
        if {[dict exists $d $key]} {dict get $d $key} else {set default}
    }

    proc list {} {
        lmap w [TkX::list_windows] {
            set id [dict get $w id]
            set props [TkX::get_props [scan $id %x]]
            dict set w role [dget $props role [dict get $w class]]
            dict set w pid [dict get $props pid]
            set cmd [dict get $props command]
            if {[llength $cmd] > 0} {
                dict set w cmdline [join $cmd " "]
            } else {
                set pid [dict get $props pid]
                if {$pid != 0 && [file exists /proc/$pid/cmdline]} {
                    catch {
                        set f [open /proc/$pid/cmdline r]
                        dict set w cmdline [string trimright [string map {\x00 " "} [read $f]]]
                        close $f
                    }
                }
                if {![dict exists $w cmdline]} { dict set w cmdline "" }
            }
            set w
        }
    }

    proc move {id args} {
        set winId [scan $id %x]
        switch [llength $args] {
            2 { lassign $args x y; TkX::move_window $winId $x $y -1 -1 }
            3 { lassign $args desktop x y; TkX::set_desktop $winId $desktop; TkX::move_window $winId $x $y -1 -1 }
            4 { lassign $args x y w h; TkX::move_window $winId $x $y $w $h }
            5 { lassign $args desktop x y w h; TkX::set_desktop $winId $desktop; TkX::move_window $winId $x $y $w $h }
            default { error "usage: win::move id ?desktop? x y ?w h?" }
        }
    }

    proc state {id action args} {
        if {[llength $args] == 0} { error "usage: win::state id add|remove|toggle prop ?prop?" }
        set winId [scan $id %x]
        set prop1 "_NET_WM_STATE_[string toupper [lindex $args 0]]"
        set prop2 [expr {[llength $args] > 1 ? "_NET_WM_STATE_[string toupper [lindex $args 1]]" : ""}]
        TkX::window_state $winId $action $prop1 $prop2
    }

    proc set_role {id role} {
        TkX::set_property [scan $id %x] WM_WINDOW_ROLE $role
    }

    proc set_command {id cmd} {
        TkX::set_property [scan $id %x] WM_COMMAND $cmd
    }

    proc get_size_hints {id} {
        TkX::get_size_hints [scan $id %x]
    }

    proc pixels_to_units {pw ph hints} {
        if {$hints eq "" || ![dict exists $hints inc_w]} {return [::list $pw $ph]}
        set inc_w [dict get $hints inc_w]
        set inc_h [dict get $hints inc_h]
        if {$inc_w <= 1 && $inc_h <= 1} {return [::list $pw $ph]}
        set base_w [dget $hints base_w 0]
        set base_h [dget $hints base_h 0]
        ::list [expr {($pw - $base_w) / $inc_w}] [expr {($ph - $base_h) / $inc_h}]
    }

    proc units_to_pixels {uw uh hints} {
        if {$hints eq "" || ![dict exists $hints inc_w]} {return [::list $uw $uh]}
        set inc_w [dict get $hints inc_w]
        set inc_h [dict get $hints inc_h]
        if {$inc_w <= 1 && $inc_h <= 1} {return [::list $uw $uh]}
        set base_w [dget $hints base_w 0]
        set base_h [dget $hints base_h 0]
        ::list [expr {$base_w + ($uw * $inc_w)}] [expr {$base_h + ($uh * $inc_h)}]
    }

    proc parse_geometry {geom {screenw 0} {screenh 0}} {
        if {$screenw == 0} { catch {set screenw [winfo screenwidth .]}; if {$screenw == 0} {set screenw 1920} }
        if {$screenh == 0} { catch {set screenh [winfo screenheight .]}; if {$screenh == 0} {set screenh 1080} }
        if {[regexp {^(\d+)x(\d+)([+-])(-?\d+)([+-])(-?\d+)$} $geom -> w h xs x ys y]} {
            if {$xs eq "-" && $x >= 0} { set x [expr {$screenw - $x - $w}] }
            if {$ys eq "-" && $y >= 0} { set y [expr {$screenh - $y - $h}] }
            return [dict create w $w h $h x $x y $y]
        }
        error "invalid geometry: $geom"
    }
}
