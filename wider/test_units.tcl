#!/usr/bin/env tclsh
# Unit tests for windows.tcl and slots.tcl

set script_dir [file dirname [info script]]
lappend auto_path [file join $script_dir .. tkx lib]
source [file join $script_dir windows.tcl]
source [file join $script_dir slots.tcl]

set pass 0
set fail 0

proc test {name body expected} {
    global pass fail
    set result [uplevel 1 $body]
    if {$result eq $expected} {
        puts "PASS: $name"
        incr pass
    } else {
        puts "FAIL: $name"
        puts "  Expected: $expected"
        puts "  Got:      $result"
        incr fail
    }
}

proc test_error {name body pattern} {
    global pass fail
    if {[catch {uplevel 1 $body} err]} {
        if {[string match $pattern $err]} {
            puts "PASS: $name"
            incr pass
        } else {
            puts "FAIL: $name (wrong error)"
            puts "  Expected: $pattern"
            puts "  Got:      $err"
            incr fail
        }
    } else {
        puts "FAIL: $name (no error thrown)"
        incr fail
    }
}

puts "=== parse_geometry tests ===\n"

test "parse basic geometry" {
    win::parse_geometry "800x600+100+50"
} {w 800 h 600 x 100 y 50}

test "parse zero position" {
    win::parse_geometry "1920x1080+0+0"
} {w 1920 h 1080 x 0 y 0}

test "parse large values" {
    win::parse_geometry "2560x1440+3840+0"
} {w 2560 h 1440 x 3840 y 0}

test_error "reject invalid geometry" {
    win::parse_geometry "invalid"
} {invalid geometry:*}

test_error "reject partial geometry" {
    win::parse_geometry "800x600"
} {invalid geometry:*}

puts "\n=== slot file I/O tests ===\n"

set test_dir [file join /tmp wider-test-[pid]]
file mkdir $test_dir

# Test slot save/load roundtrip (list format)
set slot::data [list \
    [dict create role terminal-left class Xfce4-terminal x 0 y 0 w 960 h 1080 command {xfce4-terminal --role=terminal-left}] \
    [dict create role browser class Firefox x 960 y 0 w 960 h 1080 command firefox] \
]

set slots_file [file join $test_dir slots.tcl]
slot::save $slots_file

test "slots file created" {
    file exists $slots_file
} 1

# Reload and verify
set slot::data {}
set count [slot::load $slots_file]

test "load returns slot count" {
    expr {$count == 2}
} 1

# Find slot by role
proc find_slot {role} {
    foreach slot [slot::all] {
        if {[dict get $slot role] eq $role} {
            return $slot
        }
    }
    return {}
}

test "slot role preserved" {
    dict get [find_slot terminal-left] role
} terminal-left

test "slot class preserved" {
    dict get [find_slot browser] class
} Firefox

test "slot geometry parsed" {
    dict get [find_slot terminal-left] w
} 960

puts "\n=== autostart generation tests ===\n"

set autostart_dir [file join $test_dir autostart]
slot::generate_autostart $autostart_dir

test "autostart dir created" {
    file isdirectory $autostart_dir
} 1

set desktop_files [glob -nocomplain -directory $autostart_dir *.desktop]
test "desktop files created" {
    expr {[llength $desktop_files] == 2}
} 1

# Check content of one file
set content [read [open [lindex $desktop_files 0] r]]
test "desktop file has role" {
    expr {[string match "*--role=terminal-left*" $content] || [string match "*--role=browser*" $content]}
} 1

puts "\n=== slot_distance tests ===\n"

set slot1 [dict create x 0 y 0 w 100 h 100 role slot1]
set slot2 [dict create x 200 y 0 w 100 h 100 role slot2]

# Mock window at slot1 position
set win1 {x 0 y 0 w 100 h 100}
test "window at slot position has zero distance" {
    expr {[slot::distance_to $win1 $slot1] < 1}
} 1

# Mock window between slots
set win2 {x 100 y 0 w 100 h 100}
test "window between slots has equal distance" {
    set d1 [slot::distance_to $win2 $slot1]
    set d2 [slot::distance_to $win2 $slot2]
    expr {abs($d1 - $d2) < 1}
} 1

puts "\n=== Cleanup ===\n"

file delete -force $test_dir
puts "Cleaned up $test_dir"

puts "\n=== Results ===\n"
puts "$pass passed, $fail failed"
exit [expr {$fail > 0}]
