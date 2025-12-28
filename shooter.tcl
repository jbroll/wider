#!/usr/bin/env tclsh
#
# shooter.tcl - Screenshot region capture with Peek-style frame
#
# Uses xgetimage to capture root window as background (fake transparency)
# Creates an empty frame window where the desktop shows through
#

lappend auto_path [file dirname [info script]]
lappend auto_path [file join [file dirname [info script]] lib]
package require Tk
package require xgetimage

# ----------------------------
# Paths
# ----------------------------
set configFile [file normalize ~/.screenshot]
set outDir     [file normalize ~/Documents/Screenshots]
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
set BORDER 4         ;# Frame border thickness
set TOOLBAR_H 32     ;# Bottom toolbar height

# ----------------------------
# State
# ----------------------------
array set S {
    mode ""
    hx   0
    hy   0
    lastX 0
    lastY 0
    border 0
}

# ----------------------------
# Get screen dimensions
# ----------------------------
set screenW [winfo screenwidth .]
set screenH [winfo screenheight .]

# ----------------------------
# Start withdrawn, capture root, then show
# ----------------------------
wm withdraw .
wm title . "Screenshot"

# Capture the root window BEFORE showing our window
image create photo rootimg
xgetimage::capture rootimg root 0 0 $screenW $screenH

# ----------------------------
# Build the frame-style window
# ----------------------------

# Main container
frame .main -bg #333333

# Top border (draggable) - hidden by default
frame .main.top -height $BORDER -bg #333333 -cursor fleur

# Bottom area with toolbar
frame .main.bottom -bg #333333

# Left border - hidden by default
frame .main.bottom.left -width $BORDER -bg #333333 -cursor fleur

# Right border - hidden by default
frame .main.bottom.right -width $BORDER -bg #333333 -cursor fleur

# Center area (canvas + toolbar)
frame .main.bottom.center -bg #333333

# Canvas showing "through" to desktop
set cw [dict get $region w]
set ch [dict get $region h]
canvas .main.bottom.center.c -highlightthickness 0 -width $cw -height $ch -bg black
.main.bottom.center.c create image 0 0 -anchor nw -image rootimg -tags bg
pack .main.bottom.center.c -side top -fill both -expand 1

# Toolbar
frame .main.bottom.center.toolbar -height $TOOLBAR_H -bg #333333
set sizeVar "${cw} x ${ch}"
entry .main.bottom.center.toolbar.size -textvariable sizeVar -font {Helvetica 12 bold} \
    -width 12 -justify center -bg #222222 -fg white -relief flat -insertbackground white
button .main.bottom.center.toolbar.capture -text "Capture" -command doCapture \
    -bg #444444 -fg white -relief flat -padx 10
button .main.bottom.center.toolbar.quit -text "Quit" -command doExit \
    -bg #444444 -fg white -relief flat -padx 10
button .main.bottom.center.toolbar.border -text "Border" -command toggleBorder \
    -bg #444444 -fg white -relief flat -padx 10
pack .main.bottom.center.toolbar.size -side left -padx 5 -pady 4
pack .main.bottom.center.toolbar.border -side left -padx 5 -pady 4
pack .main.bottom.center.toolbar.quit -side right -padx 5 -pady 4
pack .main.bottom.center.toolbar.capture -side right -padx 5 -pady 4
pack .main.bottom.center.toolbar -side bottom -fill x

pack .main.bottom.center -side left -fill both -expand 1
pack .main.bottom -side top -fill both -expand 1
pack .main -fill both -expand 1

# ----------------------------
# Position window and update background offset
# ----------------------------
proc updateBgOffset {} {
    global S screenW screenH BORDER sizeVar

    # Get window position on screen
    set wx [winfo rootx .main.bottom.center.c]
    set wy [winfo rooty .main.bottom.center.c]
    set cw [winfo width .main.bottom.center.c]
    set ch [winfo height .main.bottom.center.c]

    # Update size display
    set sizeVar "${cw} x ${ch}"

    # Only update image offset if position changed
    if {$wx == $S(lastX) && $wy == $S(lastY)} return
    set S(lastX) $wx
    set S(lastY) $wy

    # Offset the background image so it aligns with the screen
    .main.bottom.center.c coords bg [expr {-$wx}] [expr {-$wy}]
}

# Toggle border visibility
proc toggleBorder {} {
    global S BORDER
    set S(border) [expr {!$S(border)}]
    if {$S(border)} {
        pack .main.top -side top -fill x -before .main.bottom
        pack .main.bottom.left -side left -fill y -before .main.bottom.center
        pack .main.bottom.right -side right -fill y -before .main.bottom.center
    } else {
        pack forget .main.top
        pack forget .main.bottom.left
        pack forget .main.bottom.right
    }
}

# Initial geometry (no border by default)
set wx [dict get $region x]
set wy [dict get $region y]
set ww [dict get $region w]
set wh [expr {[dict get $region h] + $TOOLBAR_H}]
wm geometry . ${ww}x${wh}+${wx}+${wy}

# ----------------------------
# Track window movement via Configure events
# ----------------------------
bind . <Configure> {
    after cancel updateBgOffset
    after idle updateBgOffset
}

# ----------------------------
# Dragging from borders
# ----------------------------
foreach w {.main.top .main.bottom.left .main.bottom.right} {
    bind $w <ButtonPress-1> {
        set S(mode) drag
        set S(hx) %X
        set S(hy) %Y
    }
    bind $w <B1-Motion> {
        if {$S(mode) ne "drag"} return
        set dx [expr {%X - $S(hx)}]
        set dy [expr {%Y - $S(hy)}]
        set geom [wm geometry .]
        regexp {(\d+)x(\d+)\+(-?\d+)\+(-?\d+)} $geom -> gw gh gx gy
        wm geometry . ${gw}x${gh}+[expr {$gx+$dx}]+[expr {$gy+$dy}]
        set S(hx) %X
        set S(hy) %Y
    }
    bind $w <ButtonRelease-1> {
        set S(mode) ""
    }
}

# ----------------------------
# Resize from corners (optional - use WM decorations for now)
# ----------------------------

# ----------------------------
# Size entry
# ----------------------------
bind .main.bottom.center.toolbar.size <Return> {
    if {[regexp {(\d+)\s*x\s*(\d+)} $sizeVar -> newW newH]} {
        global BORDER TOOLBAR_H region
        set ww [expr {$newW + 2*$BORDER}]
        set wh [expr {$newH + $BORDER + $TOOLBAR_H}]
        set geom [wm geometry .]
        regexp {\+(-?\d+)\+(-?\d+)} $geom -> gx gy
        wm geometry . ${ww}x${wh}+${gx}+${gy}
        .main.bottom.center.c configure -width $newW -height $newH
        dict set region w $newW
        dict set region h $newH
    }
    focus .
}

# ----------------------------
# Capture - recapture live root
# ----------------------------
proc doCapture {} {
    global region outDir configFile screenW screenH BORDER TOOLBAR_H

    set ts [clock format [clock seconds] -format "%Y-%m-%d-%H:%M:%S"]
    set out [file join $outDir "screenshot-$ts.png"]

    # Update region from current window position/size
    set x [winfo rootx .main.bottom.center.c]
    set y [winfo rooty .main.bottom.center.c]
    set w [winfo width .main.bottom.center.c]
    set h [winfo height .main.bottom.center.c]
    dict set region x $x
    dict set region y $y
    dict set region w $w
    dict set region h $h

    # Hide our window
    wm withdraw .
    update
    after 150

    # Recapture the live root window
    image create photo liveroot
    xgetimage::capture liveroot root 0 0 $screenW $screenH

    # Crop to selection region
    image create photo cropped
    cropped copy liveroot -from $x $y [expr {$x+$w}] [expr {$y+$h}]

    # Show preview
    toplevel .p
    wm title .p "Preview - Enter=Save, Escape=Cancel"
    wm geometry .p +${x}+${y}
    wm attributes .p -topmost 1

    label .p.i -image cropped
    pack .p.i

    frame .p.b
    button .p.b.ok -text Save -command [list doSave cropped $out]
    button .p.b.cancel -text Cancel -command doExit
    pack .p.b.ok .p.b.cancel -side left -padx 10
    pack .p.b

    bind .p <Return> [list doSave cropped $out]
    bind .p <Escape> doExit
    focus -force .p
}

proc saveConfig {} {
    global region configFile
    set f [open $configFile w]
    puts $f $region
    close $f
}

proc doExit {} {
    global region
    # Update region from current window position/size
    dict set region x [winfo rootx .main.bottom.center.c]
    dict set region y [winfo rooty .main.bottom.center.c]
    dict set region w [winfo width .main.bottom.center.c]
    dict set region h [winfo height .main.bottom.center.c]
    saveConfig
    exit
}

proc doSave {imgname out} {
    $imgname write $out -format png
    doExit
}

# ----------------------------
# Show window and handle input
# ----------------------------
wm deiconify .
wm attributes . -topmost 1
update idletasks
after idle updateBgOffset

bind . <Return> doCapture
bind . <Escape> doExit
bind . <Key-q> doExit
