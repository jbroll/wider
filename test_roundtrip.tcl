#!/usr/bin/env tclsh
# Test position round-trip for all windows

source [file join [file dirname [info script]] wmctrl.tcl]

puts "=== Window Position Roundtrip Test ===\n"

# Capture original positions
set before {}
foreach win [wm::windows] {
    set id [dict get $win id]
    set class [dict get $win class]
    set desktop [dict get $win desktop]

    if {$desktop == -1} continue
    if {$class eq "Wider.tcl"} continue

    set x [dict get $win x]
    set y [dict get $win y]
    dict set before $id [list $class $x $y]
    puts "$class: x=$x y=$y"
}

puts "\nSaving layout..."
wm::save /tmp/test_layout.tcl
after 200

puts "Restoring layout..."
wm::restore /tmp/test_layout.tcl
after 500

puts "\n=== Results ===\n"
set pass 0
set fail 0

foreach win [wm::windows] {
    set id [dict get $win id]
    set class [dict get $win class]
    set desktop [dict get $win desktop]

    if {$desktop == -1} continue
    if {$class eq "Wider.tcl"} continue

    if {[dict exists $before $id]} {
        lassign [dict get $before $id] _ bx by
        set x [dict get $win x]
        set y [dict get $win y]
        set dx [expr {$x - $bx}]
        set dy [expr {$y - $by}]

        if {abs($dx) <= 2 && abs($dy) <= 2} {
            puts "$class: PASS"
            incr pass
        } else {
            puts "$class: FAIL (shifted by $dx,$dy)"
            incr fail
        }
    }
}

puts "\n$pass passed, $fail failed"
exit [expr {$fail > 0}]
