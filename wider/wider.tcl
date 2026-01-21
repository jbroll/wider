#!/home/john/bin/wish9.1
# wider.tcl - Window layout save/restore utility
#
# Usage:
#   wider.tcl              - GUI mode (with slot monitoring)
#   wider.tcl --restore    - restore layout and exit
#   wider.tcl --save       - save layout and exit
#   wider.tcl --arrange    - arrange windows to slots and exit
#   wider.tcl --launch     - launch missing apps from slots and exit
#   wider.tcl --generate   - generate slots.tcl from layout.tcl
#   wider.tcl --autostart  - generate autostart .desktop files from slots

# Resolve symlinks to find actual script location
set script [file normalize [info script]]
while {[file type $script] eq "link"} {
    set script [file join [file dirname $script] [file readlink $script]]
}
set script_dir [file dirname [file normalize $script]]
lappend auto_path [file join $script_dir .. tkx lib]
tcl::tm::path add $env(HOME)/lib/tcl8/site-tcl
source [file join $script_dir windows.tcl]
source [file join $script_dir slots.tcl]

# CLI mode - handle before loading Tk
if {[llength $argv] > 0} {
    switch -- [lindex $argv 0] {
        --restore - -r {
            set count [slot::restore_layout]
            puts "Restored $count windows"
            exit 0
        }
        --save - -s {
            set count [slot::save_layout]
            puts "Saved $count windows"
            exit 0
        }
        --arrange - -a {
            slot::load
            set count [slot::arrange_all]
            puts "Arranged $count windows"
            exit 0
        }
        --launch - -l {
            slot::load
            set count [slot::launch_all]
            puts "Launched $count apps"
            exit 0
        }
        --generate - -g {
            set count [slot::generate_from_layout]
            puts "Generated $count slots from layout"
            exit 0
        }
        --autostart {
            slot::load
            set count [slot::generate_autostart]
            puts "Generated $count autostart files in ~/.config/autostart/"
            exit 0
        }
        --help - -h {
            puts "Usage: wider.tcl \[option\]"
            puts "  --restore, -r   Restore window layout and exit"
            puts "  --save, -s      Save window layout and exit"
            puts "  --arrange, -a   Arrange windows to slots and exit"
            puts "  --launch, -l    Launch missing apps from slots and exit"
            puts "  --generate, -g  Generate slots.tcl from layout.tcl"
            puts "  --autostart     Generate autostart .desktop files from slots"
            puts "  (no args)       Run GUI with slot monitoring"
            exit 0
        }
        default {
            puts stderr "Unknown option: [lindex $argv 0]"
            exit 1
        }
    }
}

# ========== GUI Mode ==========

package require Tk
package require jbr::layout
package require jbr::func
source /home/john/src/jbr.tcl/layout/layoutscroll.tcl

# Single instance enforcement
proc check_single_instance {} {
    set port 47824  ;# Unique port for wider (talkie uses 47823)

    # Try to connect to existing instance
    if {![catch {socket localhost $port} sock]} {
        puts $sock "raise"
        flush $sock
        close $sock
        exit 0
    }

    # No existing instance - become the server
    socket -server handle_instance_request $port
}

proc handle_instance_request {sock addr port} {
    if {[gets $sock line] >= 0 && $line eq "raise"} {
        wm deiconify .
        raise .
        focus -force .
    }
    close $sock
}

check_single_instance

# Load slot configuration
slot::load

# Source GUI modules
source [file join $script_dir monitor.tcl]
source [file join $script_dir winlist.tcl]
source [file join $script_dir ui.tcl]
