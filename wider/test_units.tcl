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

puts "\n=== slot file I/O tests (new format) ===\n"

set test_dir [file join /tmp wider-test-[pid]]
file mkdir $test_dir

# Set up role-centric data
set slot::data [dict create \
    terminal-left [dict create \
        class Xfce4-terminal \
        command {xfce4-terminal --role=terminal-left} \
        positions [list [dict create x 0 y 0 w 960 h 1080]]] \
    browser [dict create \
        class Firefox \
        command firefox \
        positions [list [dict create x 960 y 0 w 960 h 1080]]] \
]

set slots_file [file join $test_dir slots.tcl]
slot::save $slots_file

test "slots file created" {
    file exists $slots_file
} 1

# Reload and verify
set slot::data {}
set count [slot::load $slots_file]

test "load returns position count" {
    expr {$count == 2}
} 1

test "role exists after load" {
    dict exists [slot::all] terminal-left
} 1

test "role class preserved" {
    dict get [dict get [slot::all] browser] class
} Firefox

test "role command preserved" {
    dict get [dict get [slot::all] terminal-left] command
} {xfce4-terminal --role=terminal-left}

test "position geometry preserved" {
    dict get [lindex [dict get [dict get [slot::all] terminal-left] positions] 0] w
} 960

puts "\n=== slot::positions flat list ===\n"

set flat [slot::positions]
test "positions returns flat list" {
    llength $flat
} 2

test "flat position has role" {
    dict get [lindex $flat 0] role
} terminal-left

test "flat position has class" {
    dict get [lindex $flat 0] class
} Xfce4-terminal

test "flat position has command" {
    dict get [lindex $flat 0] command
} {xfce4-terminal --role=terminal-left}

test "flat position has geometry" {
    dict get [lindex $flat 0] x
} 0

puts "\n=== backward compat: load old format ===\n"

set old_file [file join $test_dir old_slots.tcl]
set f [open $old_file w]
puts $f {slot {
    role     terminal
    class    Xfce4-terminal
    geometry 960x1080+0+0
    command  {xfce4-terminal --role=terminal}
}

slot {
    role     terminal
    class    Xfce4-terminal
    geometry 960x1080+960+0
    command  {xfce4-terminal --role=terminal --geometry=960x1080+960+0}
}

slot {
    role     browser
    class    Firefox
    geometry 960x1080+960+0
    command  {/usr/bin/firefox}
}}
close $f

set slot::data {}
set count [slot::load $old_file]

test "old format loads" {
    expr {$count == 3}
} 1

test "old format groups by role" {
    llength [dict keys [slot::all]]
} 2

test "terminal has 2 positions" {
    llength [dict get [dict get [slot::all] terminal] positions]
} 2

test "browser has 1 position" {
    llength [dict get [dict get [slot::all] browser] positions]
} 1

test "old format strips stale --geometry from command" {
    dict get [dict get [slot::all] terminal] command
} {xfce4-terminal --role=terminal}

puts "\n=== multi-position role tests ===\n"

set slot::data [dict create \
    terminal [dict create \
        class Xfce4-terminal \
        command {xfce4-terminal --role=terminal} \
        positions [list \
            [dict create x 0 y 0 w 960 h 1080] \
            [dict create x 960 y 0 w 960 h 1080] \
            [dict create x 0 y 1080 w 960 h 1080]]] \
]

test "find_position by proximity" {
    slot::find_position terminal 5 5
} 0

test "find_position second slot" {
    slot::find_position terminal 965 5
} 1

test "find_position no match" {
    slot::find_position terminal 5000 5000
} -1

test "add_position to existing role" {
    slot::add_position terminal [dict create x 960 y 1080 w 960 h 1080]
    llength [dict get [dict get [slot::all] terminal] positions]
} 4

test "add_position creates new role" {
    slot::add_position mail [dict create x 0 y 0 w 800 h 600] Thunderbird thunderbird
    dict exists [slot::all] mail
} 1

test "remove_position" {
    slot::remove_position terminal 3
    llength [dict get [dict get [slot::all] terminal] positions]
} 3

test "remove last position removes role" {
    slot::remove_position mail 0
    dict exists [slot::all] mail
} 0

puts "\n=== replace_all (Save rebuild) tests ===\n"

# Seed with junk: duplicate positions and a stale role, like a corrupted
# slots.tcl produced by the old accumulating Save.
set slot::data [dict create \
    browser [dict create class Firefox command firefox positions [list \
        [dict create x 0 y 0 w 100 h 100] \
        [dict create x 0 y 0 w 100 h 100] \
        [dict create x 0 y 0 w 100 h 100]]] \
    stale [dict create class Stale command stale positions [list \
        [dict create x 9 y 9 w 9 h 9]]] \
]

test "replace_all drops stale roles" {
    slot::replace_all [dict create \
        browser [dict create class Firefox command firefox positions [list \
            [dict create x 10 y 20 w 800 h 600]]]]
    dict exists [slot::all] stale
} 0

test "replace_all removes accumulated duplicate positions" {
    llength [dict get [dict get [slot::all] browser] positions]
} 1

test "replace_all keeps the new position values" {
    dict get [lindex [dict get [dict get [slot::all] browser] positions] 0] x
} 10

test "replace_all with empty dict clears everything" {
    slot::replace_all {}
    dict size [slot::all]
} 0

puts "\n=== autostart generation tests ===\n"

set slot::data [dict create \
    terminal [dict create \
        class Xfce4-terminal \
        command {xfce4-terminal --role=terminal} \
        positions [list \
            [dict create x 0 y 0 w 960 h 1080] \
            [dict create x 960 y 0 w 960 h 1080]]] \
    browser [dict create \
        class Firefox \
        command {/usr/bin/firefox} \
        positions [list [dict create x 960 y 0 w 960 h 1080]]] \
]

set autostart_dir [file join $test_dir autostart]
slot::generate_autostart $autostart_dir

test "autostart dir created" {
    file isdirectory $autostart_dir
} 1

set desktop_files [lsort [glob -nocomplain -directory $autostart_dir *.desktop]]
test "desktop files created (one per position)" {
    llength $desktop_files
} 3

# Check naming is role-based
test "desktop file named by role" {
    file tail [lindex $desktop_files 0]
} wider-browser-1.desktop

# Check terminal desktop files have --geometry
set term_file [lindex $desktop_files 1]
set content [read [open $term_file r]]
test "terminal autostart has --geometry" {
    string match "*--geometry=960x1080+0+0*" $content
} 1

test "terminal autostart has --role" {
    string match "*--role=terminal*" $content
} 1

# Check browser doesn't get --geometry appended
set browser_file [lindex $desktop_files 0]
set bcontent [read [open $browser_file r]]
test "browser autostart has --role appended" {
    string match "*--role=browser*" $bcontent
} 1

puts "\n=== distance_to tests ===\n"

set pos1 [dict create x 0 y 0 w 100 h 100]
set pos2 [dict create x 200 y 0 w 100 h 100]

set win1 {x 0 y 0 w 100 h 100}
test "window at position has zero distance" {
    expr {[slot::distance_to $win1 $pos1] < 1}
} 1

set win2 {x 100 y 0 w 100 h 100}
test "window between positions has equal distance" {
    set d1 [slot::distance_to $win2 $pos1]
    set d2 [slot::distance_to $win2 $pos2]
    expr {abs($d1 - $d2) < 1}
} 1

puts "\n=== save/load roundtrip (new format) ===\n"

set slot::data [dict create \
    terminal [dict create \
        class Xfce4-terminal \
        command {xfce4-terminal --role=terminal} \
        positions [list \
            [dict create x 0 y 0 w 100 h 57] \
            [dict create x 960 y 0 w 100 h 57]]] \
    browser [dict create \
        class Firefox \
        command {/usr/bin/firefox} \
        positions [list [dict create x 960 y 0 w 1402 h 1747]]] \
]

set rt_file [file join $test_dir roundtrip.tcl]
slot::save $rt_file
set slot::data {}
slot::load $rt_file

test "roundtrip preserves role count" {
    llength [dict keys [slot::all]]
} 2

test "roundtrip preserves terminal positions" {
    llength [dict get [dict get [slot::all] terminal] positions]
} 2

test "roundtrip preserves browser command" {
    dict get [dict get [slot::all] browser] command
} {/usr/bin/firefox}

test "roundtrip preserves position values" {
    dict get [lindex [dict get [dict get [slot::all] terminal] positions] 1] x
} 960

puts "\n=== Cleanup ===\n"

file delete -force $test_dir
puts "Cleaned up $test_dir"

puts "\n=== Results ===\n"
puts "$pass passed, $fail failed"
exit [expr {$fail > 0}]
