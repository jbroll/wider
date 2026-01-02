#!/usr/bin/env tclsh
# Unit tests for wmctrl.tcl pure functions

source [file join [file dirname [info script]] wmctrl.tcl]

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
    wm::parse_geometry "800x600+100+50"
} {w 800 h 600 x 100 y 50}

test "parse zero position" {
    wm::parse_geometry "1920x1080+0+0"
} {w 1920 h 1080 x 0 y 0}

test "parse large values" {
    wm::parse_geometry "2560x1440+3840+0"
} {w 2560 h 1440 x 3840 y 0}

test_error "reject invalid geometry" {
    wm::parse_geometry "invalid"
} {invalid geometry:*}

test_error "reject partial geometry" {
    wm::parse_geometry "800x600"
} {invalid geometry:*}

puts "\n=== slot file I/O tests ===\n"

set test_dir [file join /tmp wider-test-[pid]]
file mkdir $test_dir

# Test slot save/load roundtrip
set wm::slots {
    terminal-left {
        role terminal-left
        class Xfce4-terminal
        x 0 y 0 w 960 h 1080
        command {xfce4-terminal --role=terminal-left}
    }
    browser {
        role browser
        class Firefox
        x 960 y 0 w 960 h 1080
        command firefox
    }
}

set slots_file [file join $test_dir slots.tcl]
wm::save_slots $slots_file

test "slots file created" {
    file exists $slots_file
} 1

# Reload and verify
set wm::slots {}
set count [wm::load_slots $slots_file]

test "load returns slot count" {
    expr {$count == 2}
} 1

test "slot role preserved" {
    dict get $wm::slots terminal-left role
} terminal-left

test "slot class preserved" {
    dict get $wm::slots browser class
} Firefox

test "slot geometry parsed" {
    dict get $wm::slots terminal-left w
} 960

puts "\n=== autostart generation tests ===\n"

set autostart_dir [file join $test_dir autostart]
wm::generate_autostart $autostart_dir

test "autostart dir created" {
    file isdirectory $autostart_dir
} 1

set desktop_files [glob -nocomplain -directory $autostart_dir *.desktop]
test "desktop files created" {
    expr {[llength $desktop_files] == 2}
} 1

# Check content of one file
set content [read [open [file join $autostart_dir wider-terminal-left.desktop] r]]
test "desktop file has role" {
    string match "*--role=terminal-left*" $content
} 1

test "desktop file has X-Wider-Slot" {
    string match "*X-Wider-Slot=terminal-left*" $content
} 1

puts "\n=== slot_distance tests ===\n"

set wm::slots {
    slot1 {x 0 y 0 w 100 h 100}
    slot2 {x 200 y 0 w 100 h 100}
}

# Mock window at slot1 center
set win1 {x 0 y 0 w 100 h 100}
test "window at slot center has zero distance" {
    expr {[wm::slot_distance $win1 slot1] < 1}
} 1

# Mock window between slots
set win2 {x 100 y 0 w 100 h 100}
test "window between slots has equal distance" {
    set d1 [wm::slot_distance $win2 slot1]
    set d2 [wm::slot_distance $win2 slot2]
    expr {abs($d1 - $d2) < 1}
} 1

puts "\n=== Cleanup ===\n"

file delete -force $test_dir
puts "Cleaned up $test_dir"

puts "\n=== Results ===\n"
puts "$pass passed, $fail failed"
exit [expr {$fail > 0}]
