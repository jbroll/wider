# xgetimage.tcl - Capture X11 window/root to Tk photo image
#
# Usage: xgetimage::capture <photo> root|<window_id> x y width height
#
# Note: Tk must be loaded before this package

package require Tk

# Load the C extension
set dir [file dirname [info script]]
load [file join $dir xgetimage.so]

package provide xgetimage 0.1
