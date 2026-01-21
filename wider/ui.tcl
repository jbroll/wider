# ui.tcl - UI layout and setup
#
# Contains the main window layout, keybindings, collapsible card,
# and monitoring toggle button.

wm title . "Wider - Slot Editor"
wm resizable . 1 1
tk appname wider
set status "Ready"

# ========== Keybindings ==========

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

# ========== Collapsible Card ==========

set card_expanded 0
set saved_height 400

proc toggle_card {} {
    global card_expanded saved_height
    set card_expanded [expr {!$card_expanded}]
    set w [winfo width .]
    if {$card_expanded} {
        grid .card -in .f -row 1 -column 0 -sticky nsew
        $::ui::toggle configure -text "▼"
        wm minsize . 600 300
        wm geometry . ${w}x${saved_height}
    } else {
        set saved_height [winfo height .]
        grid forget .card
        $::ui::toggle configure -text "▶"
        update idletasks
        wm minsize . 600 0
        wm geometry . ${w}x[winfo reqheight .]
    }
}

# ========== Monitoring Toggle ==========

proc update_monitor_button {} {
    global monitoring
    $::ui::monitor configure -text [expr {$monitoring ? "Monitor: ON" : "Monitor: OFF"}] \
        -foreground [expr {$monitoring ? "darkgreen" : "gray"}]
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

# ========== Layout ==========

# UI widget references namespace
namespace eval ::ui {}

# Main layout using jbr layout DSL
col .f {
    -sticky nsew
    -padx 5
    -pady 5

    row .btns {
        -sticky ew
        -padx 3

        ! "Refresh" -command refresh_window_list
        ! "Snap" -command do_snap
        ! "Arrange" -command do_arrange
        ! "Launch" -command do_launch
        ! ::ui::monitor "Monitor: ON" -command toggle_monitoring -foreground darkgreen
        @ ::ui::status "" -textvariable status -foreground gray -anchor w
        ! ::ui::toggle "▶" -command toggle_card -width 2
    }
}
grid columnconfigure .f.btns 5 -weight 1
grid .f -sticky nsew
grid columnconfigure . 0 -weight 1
grid rowconfigure . 0 -weight 1
grid columnconfigure .f 0 -weight 1
grid rowconfigure .f 1 -weight 1

# Collapsible card with header and scrollable list
col .card -relief groove -borderwidth 1 {
    -sticky nsew

    row .hdr -background "#e0e0e0" {
        -sticky ew
        -padx 2
        -pady 3
        -label.background "#e0e0e0"
        -label.anchor w

        @ "" -width 3
        @ "Role" -width 16
        @ "Class" -width 14
        @ "Geometry" -width 20
        @ "Command" -width 30
        @ "Title"
    }
}
grid columnconfigure .card.hdr 5 -weight 1
grid columnconfigure .card 0 -weight 1
grid rowconfigure .card 1 -weight 1

# Scrollable list area using scroll container (body empty - rows added dynamically)
scroll .card.list -background white { }
.card.list.canvas.inner configure -background white
grid .card.list -in .card -row 1 -column 0 -sticky nsew

wm minsize . 600 0

# ========== Initial Setup ==========

proc setup_window {} {
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

after idle {
    update idletasks
    setup_window
}
