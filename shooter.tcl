#!/usr/bin/env wish
#
# shooter.tcl - Screenshot region capture with true transparency
#

# Require 32-bit visual
if {[winfo depth .] != 32} {
    puts stderr "ERROR: Need 32-bit visual. Run the 'shooter' wrapper script."
    exit 1
}

# Find script directory
set scriptDir [file dirname [info script]]
if {$scriptDir eq "" || $scriptDir eq "."} {
    set scriptDir [pwd]
}
set scriptDir [file normalize $scriptDir]

lappend auto_path $scriptDir
lappend auto_path [file join $scriptDir lib]
package require TkX

# ----------------------------
# Paths
# ----------------------------
set configFile [file join $env(HOME) .screenshot]
set outDir     [file join $env(HOME) Documents Screenshots]
file mkdir $outDir

# ----------------------------
# Defaults
# ----------------------------
set region {x 200 y 200 w 500 h 400}

if {[file exists $configFile]} {
    catch {
        set f [open $configFile r]
        set region [dict merge $region [read $f]]
        close $f
    }
}

# ----------------------------
# Constants
# ----------------------------
set TOOLBAR_H 32
set BORDER 6
set CORNER_SIZE 16

# ----------------------------
# State
# ----------------------------
set winW [dict get $region w]
set winH [dict get $region h]
set winX [dict get $region x]
set winY [dict get $region y]

# ----------------------------
# Configure root window for transparency
# ----------------------------
. configure -background ""
wm geometry . [expr {$winW + 2*$BORDER}]x[expr {$winH + $TOOLBAR_H + 2*$BORDER}]+${winX}+${winY}
wm overrideredirect . 1
update

# Toolbar frame
frame .toolbar -bg "#3c3c3c" -height $TOOLBAR_H
pack .toolbar -fill x

# Toolbar buttons
button .toolbar.capture -text "Capture" -relief flat \
    -bg "#27ae60" -fg white -activebackground "#2ecc71" -activeforeground white \
    -font {Helvetica 10 bold} -padx 8 -pady 2 -command doCapture
button .toolbar.menu -text "Size" -relief flat \
    -bg "#3c3c3c" -fg white -activebackground "#505050" -activeforeground white \
    -font {Helvetica 10} -padx 8 -pady 2 -command showPanel
button .toolbar.close -text "X" -relief flat \
    -bg "#3c3c3c" -fg white -activebackground "#e74c3c" -activeforeground white \
    -font {Helvetica 10 bold} -width 2 -command doExit

pack .toolbar.capture -side left -padx 4 -pady 2
pack .toolbar.close -side right -padx 4 -pady 2
pack .toolbar.menu -side right -padx 4 -pady 2

# Drag area (middle of toolbar)
frame .toolbar.drag -bg "#3c3c3c" -height $TOOLBAR_H
pack .toolbar.drag -side left -fill both -expand 1

# ----------------------------
# Dropdown panel
# ----------------------------
frame .panel -bg "#3c3c3c" -bd 1 -relief solid

# Size presets
label .panel.title -text "Capture Size" -bg "#3c3c3c" -fg "#888888" \
    -font {Helvetica 9}
pack .panel.title -fill x -pady 5

foreach {label w h} {
    "640 × 480" 640 480
    "800 × 600" 800 600
    "1280 × 720" 1280 720
    "1920 × 1080" 1920 1080
} {
    button .panel.b${w}x${h} -text $label -bg "#3c3c3c" -fg white \
        -activebackground "#505050" -activeforeground white \
        -relief flat -anchor w -padx 10 \
        -command [list setSize $w $h]
    pack .panel.b${w}x${h} -fill x
}

# Separator
frame .panel.sep1 -bg "#606060" -height 1
pack .panel.sep1 -fill x -pady 5

# Custom size entry
frame .panel.custom -bg "#3c3c3c"
label .panel.custom.l -text "Custom:" -bg "#3c3c3c" -fg white
entry .panel.custom.e -width 12 -bg "#505050" -fg white \
    -insertbackground white -font {Helvetica 10}
.panel.custom.e insert 0 "${winW}x${winH}"
button .panel.custom.set -text "Set" -bg "#27ae60" -fg white \
    -activebackground "#2ecc71" -command applyCustomSize
pack .panel.custom.l -side left -padx 5
pack .panel.custom.e -side left -padx 2
pack .panel.custom.set -side left -padx 5
pack .panel.custom -fill x -pady 5

# ----------------------------
# Panel show/hide
# ----------------------------
proc showPanel {} {
    set x [expr {[winfo width .] - [winfo reqwidth .panel] - 4}]
    place .panel -x $x -y $::TOOLBAR_H
    raise .panel
    TkX::grab_focus .
    focus -force .panel.custom.e
}

proc hidePanel {} {
    place forget .panel
    focus -force .
}

bind .panel <Escape> hidePanel
bind .panel.custom.e <Button-1> {TkX::grab_focus .; focus -force %W}
bind .panel.custom.e <Return> {applyCustomSize; break}

# ----------------------------
# Size functions
# ----------------------------
proc setSize {w h} {
    global winW winH TOOLBAR_H BORDER
    hidePanel
    set winW $w
    set winH $h
    .panel.custom.e delete 0 end
    .panel.custom.e insert 0 "${w}x${h}"
    wm geometry . [expr {$w + 2*$BORDER}]x[expr {$h + $TOOLBAR_H + 2*$BORDER}]
}

proc applyCustomSize {} {
    set size [.panel.custom.e get]
    if {[regexp {^(\d+)\s*[x×]\s*(\d+)$} $size -> w h]} {
        setSize $w $h
    }
}

# ----------------------------
# Border frames with resize cursors and inner drop shadow
# ----------------------------
set SHADOW 2
set SHADOW_COLOR "#c0c0c0"

# Border frames (same color as toolbar)
frame .border_top -bg "#3c3c3c" -height $BORDER -cursor top_side
frame .border_left -bg "#3c3c3c" -width $BORDER -cursor left_side
frame .border_right -bg "#3c3c3c" -width $BORDER -cursor right_side
frame .border_bottom -bg "#3c3c3c" -height $BORDER -cursor bottom_side

place .border_top -x $BORDER -y $TOOLBAR_H -relwidth 1.0 -width [expr {-2*$BORDER}] -height $BORDER
place .border_left -x 0 -y $TOOLBAR_H -width $BORDER -relheight 1.0 -height -$TOOLBAR_H
place .border_right -relx 1.0 -x -$BORDER -y $TOOLBAR_H -width $BORDER -relheight 1.0 -height -$TOOLBAR_H
place .border_bottom -x 0 -rely 1.0 -y -$BORDER -relwidth 1.0 -height $BORDER

# Top corner resize areas (below toolbar)
frame .corner_nw -bg "#3c3c3c" -cursor top_left_corner
frame .corner_ne -bg "#3c3c3c" -cursor top_right_corner

place .corner_nw -x 0 -y $TOOLBAR_H -width $CORNER_SIZE -height $CORNER_SIZE
place .corner_ne -relx 1.0 -x -$CORNER_SIZE -y $TOOLBAR_H -width $CORNER_SIZE -height $CORNER_SIZE

# Inner shadow (between border and transparent area)
frame .shadow_top -bg $SHADOW_COLOR
frame .shadow_left_inner -bg $SHADOW_COLOR
frame .shadow_right_inner -bg $SHADOW_COLOR
frame .shadow_bottom_inner -bg $SHADOW_COLOR

set INNER_TOP [expr {$TOOLBAR_H + $BORDER}]
place .shadow_top -x $BORDER -y $INNER_TOP -relwidth 1.0 -width [expr {-2*$BORDER}] -height $SHADOW
place .shadow_left_inner -x $BORDER -y [expr {$INNER_TOP + $SHADOW}] -width $SHADOW -relheight 1.0 -height [expr {-$INNER_TOP - $BORDER - 2*$SHADOW}]
place .shadow_right_inner -relx 1.0 -x [expr {-$BORDER - $SHADOW}] -y [expr {$INNER_TOP + $SHADOW}] -width $SHADOW -relheight 1.0 -height [expr {-$INNER_TOP - $BORDER - 2*$SHADOW}]
place .shadow_bottom_inner -x $BORDER -rely 1.0 -y [expr {-$BORDER - $SHADOW}] -relwidth 1.0 -width [expr {-2*$BORDER}] -height $SHADOW

# Corner resize areas
frame .corner_sw -bg "#3c3c3c" -cursor bottom_left_corner
frame .corner_se -bg "#3c3c3c" -cursor bottom_right_corner

place .corner_sw -x 0 -rely 1.0 -y -$CORNER_SIZE -width $CORNER_SIZE -height $CORNER_SIZE
place .corner_se -relx 1.0 -x -$CORNER_SIZE -rely 1.0 -y -$CORNER_SIZE -width $CORNER_SIZE -height $CORNER_SIZE

raise .corner_nw
raise .corner_ne
raise .corner_sw
raise .corner_se

# ----------------------------
# Move handling (drag toolbar)
# ----------------------------
bind .toolbar.drag <Button-1> {
    set ::dragStart [list %X %Y]
}
bind .toolbar.drag <B1-Motion> {
    lassign $::dragStart sx sy
    set dx [expr {%X - $sx}]
    set dy [expr {%Y - $sy}]
    set ::dragStart [list %X %Y]

    set x [winfo x .]
    set y [winfo y .]
    wm geometry . +[expr {$x + $dx}]+[expr {$y + $dy}]
}

# ----------------------------
# Resize handling
# ----------------------------
proc startResize {edge} {
    set ::resizing [list $edge [winfo pointerx .] [winfo pointery .] \
        [winfo x .] [winfo y .] [winfo width .] [winfo height .]]
}

proc doResize {edge} {
    if {![info exists ::resizing]} return
    lassign $::resizing orig_edge sx sy wx wy sw sh
    set dx [expr {[winfo pointerx .] - $sx}]
    set dy [expr {[winfo pointery .] - $sy}]

    set nx $wx
    set ny $wy
    set nw $sw
    set nh $sh

    switch $edge {
        west {
            set nx [expr {$wx + $dx}]
            set nw [expr {$sw - $dx}]
        }
        east {
            set nw [expr {$sw + $dx}]
        }
        north {
            set ny [expr {$wy + $dy}]
            set nh [expr {$sh - $dy}]
        }
        south {
            set nh [expr {$sh + $dy}]
        }
        nw {
            set nx [expr {$wx + $dx}]
            set nw [expr {$sw - $dx}]
            set ny [expr {$wy + $dy}]
            set nh [expr {$sh - $dy}]
        }
        ne {
            set nw [expr {$sw + $dx}]
            set ny [expr {$wy + $dy}]
            set nh [expr {$sh - $dy}]
        }
        sw {
            set nx [expr {$wx + $dx}]
            set nw [expr {$sw - $dx}]
            set nh [expr {$sh + $dy}]
        }
        se {
            set nw [expr {$sw + $dx}]
            set nh [expr {$sh + $dy}]
        }
    }

    # Minimum size
    if {$nw < 100} {set nw 100; set nx $wx}
    if {$nh < 100} {set nh 100}

    wm geometry . ${nw}x${nh}+${nx}+${ny}
}

proc endResize {} {
    if {[info exists ::resizing]} {
        unset ::resizing
    }
}

# Bind resize events to border frames
foreach {frame edge} {
    .border_top north .border_left west .border_right east .border_bottom south
    .corner_nw nw .corner_ne ne .corner_sw sw .corner_se se
} {
    bind $frame <Button-1> [list startResize $edge]
    bind $frame <B1-Motion> [list doResize $edge]
    bind $frame <ButtonRelease-1> endResize
}

# ----------------------------
# Capture
# ----------------------------
proc doCapture {} {
    global winW winH TOOLBAR_H BORDER outDir

    set ts [clock format [clock seconds] -format "%Y-%m-%d-%H%M%S"]
    set out [file join $outDir "screenshot-$ts.png"]

    # Get capture region (inside border)
    set x [expr {[winfo rootx .] + $BORDER}]
    set y [expr {[winfo rooty .] + $TOOLBAR_H + $BORDER}]
    set w [expr {[winfo width .] - 2*$BORDER}]
    set h [expr {[winfo height .] - $TOOLBAR_H - 2*$BORDER}]

    # Hide window
    hidePanel
    wm withdraw .
    update
    after 150

    # Capture
    image create photo capture
    TkX::capture capture root $x $y $w $h

    # Show preview
    toplevel .preview
    wm title .preview "Preview - Enter=Save, Escape=Cancel"
    wm geometry .preview +$x+$y

    label .preview.img -image capture
    pack .preview.img

    frame .preview.btns
    button .preview.btns.save -text "Save" -command [list doSave capture $out]
    button .preview.btns.cancel -text "Cancel" -command cancelCapture
    pack .preview.btns.save .preview.btns.cancel -side left -padx 10
    pack .preview.btns -pady 10

    bind .preview <Return> [list doSave capture $out]
    bind .preview <Escape> cancelCapture
    focus -force .preview
}

proc doSave {img path} {
    $img write $path -format png
    puts "Saved: $path"
    doExit
}

proc cancelCapture {} {
    destroy .preview
    wm deiconify .
    focus -force .
}

# ----------------------------
# Exit
# ----------------------------
proc doExit {} {
    global region configFile TOOLBAR_H BORDER

    # Save position and size
    dict set region x [winfo x .]
    dict set region y [winfo y .]
    dict set region w [expr {[winfo width .] - 2*$BORDER}]
    dict set region h [expr {[winfo height .] - $TOOLBAR_H - 2*$BORDER}]

    set f [open $configFile w]
    puts $f $region
    close $f

    exit
}

# ----------------------------
# Bindings
# ----------------------------
bind . <Expose> {after idle {raise .corner_sw; raise .corner_se}}
bind . <Destroy> {if {"%W" eq "."} doExit}
bind . <Button-1> {
    if {[winfo class %W] ne "Entry"} {
        TkX::grab_focus .
        focus -force .
    }
}
bind . <Escape> doExit
bind . <Key-q> doExit
bind . <Return> doCapture

TkX::grab_focus .
focus -force .

flush stderr

# Keep window visible
tkwait window .
