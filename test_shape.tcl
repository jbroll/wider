#!/usr/bin/env tclsh
#
# test_shape.tcl - Simple shape extension test
#
# Press 'q' or Escape to quit

lappend auto_path [file join [file dirname [info script]] tkx lib]
package require Tk
package require TkX

wm geometry . 400x300+100+100
wm title . "Shape Test"

canvas .c -bg blue -highlightthickness 0
pack .c -fill both -expand 1

set applyingShape 0

proc applyShape {} {
    global applyingShape
    if {$applyingShape} return
    set applyingShape 1
    puts "Applying shape at [clock seconds]"
    # Hole at (0,0) covering full Tk window - C code handles frame offset
    TkX::bounding_hole . 0 0 400 300
    # Reset flag after a short delay to catch our own ShapeNotify
    after 50 {set applyingShape 0}
}

update
after 500
applyShape

puts "You should see:"
puts "  - Blue border around edges"
puts "  - Transparent center showing desktop"
puts "  - Title bar working normally"
puts ""
puts "Press 'r' to reapply shape, 'q' to quit"
puts "Wait and watch if shape fills in..."

bind . <Key-q> exit
bind . <Escape> exit
bind . <Key-r> applyShape

# Watch for shape changes and reapply
TkX::shape_watch . applyShape

# Enter event loop
vwait forever
