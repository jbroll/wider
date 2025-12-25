# csd.tcl - Minimal GTK-style Client-Side Decorations for Tk (X11)
#
# Provides:
#   csd::nodectk  <window>              - Remove window decorations
#   csd::move     <window>              - Initiate WM-controlled move
#   csd::resize   <window> <direction>  - Initiate WM-controlled resize
#
# Directions: north south east west nw ne sw se
#
# Note: Tk must be loaded before this package

package require Tk

# Load the C extension
set dir [file dirname [info script]]
load [file join $dir csd.so]

package provide csd 0.1
