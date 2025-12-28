#!/usr/bin/env tclsh
#
# shooter.tcl - Screenshot region capture with Peek-style frame
#
# Uses X11 Shape extension for true transparency (with compositor)
# Falls back to fake transparency (root image copy) if needed
#

lappend auto_path [file dirname [info script]]
lappend auto_path [file join [file dirname [info script]] lib]
package require Tk
package require TkX

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
set TOOLBAR_H 32     ;# Toolbar height

# ----------------------------
# State
# ----------------------------
array set S {
    mode ""
    hx   0
    hy   0
    lastX 0
    lastY 0
    display "shape"
    border 0
    applyingShape 0
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

# Capture the root window for fake transparency fallback
image create photo rootimg
TkX::capture rootimg root 0 0 $screenW $screenH

# ----------------------------
# Build the frame-style window
# ----------------------------

# Main container
frame .main -bg #333333

# Canvas showing "through" to desktop
set cw [dict get $region w]
set ch [dict get $region h]
canvas .main.c -highlightthickness 0 -width $cw -height $ch -bg black
.main.c create image 0 0 -anchor nw -image rootimg -tags bg
pack .main.c -side top -fill both -expand 1

# Toolbar
frame .main.toolbar -height $TOOLBAR_H -bg #333333
set sizeVar "${cw} x ${ch}"
entry .main.toolbar.size -textvariable sizeVar -font {Helvetica 12 bold} \
    -width 12 -justify center -bg #222222 -fg white -relief flat -insertbackground white
button .main.toolbar.capture -text "Capture" -command doCapture \
    -bg #444444 -fg white -relief flat -padx 10
button .main.toolbar.quit -text "Quit" -command doExit \
    -bg #444444 -fg white -relief flat -padx 10
button .main.toolbar.refresh -text "Refresh" -command doRefresh \
    -bg #444444 -fg white -relief flat -padx 10
menubutton .main.toolbar.options -text "Options" -menu .main.toolbar.options.m \
    -bg #444444 -fg white -relief flat -padx 10
menu .main.toolbar.options.m -tearoff 0
.main.toolbar.options.m add radiobutton -label "Shape (compositor)" \
    -variable S(display) -value "shape" -command {setDisplayMode shape}
.main.toolbar.options.m add radiobutton -label "Fake transparency" \
    -variable S(display) -value "fake" -command {setDisplayMode fake}
.main.toolbar.options.m add separator
.main.toolbar.options.m add checkbutton -label "Border" \
    -variable S(border) -command toggleBorder
pack .main.toolbar.size -side left -padx 5 -pady 4
pack .main.toolbar.refresh -side left -padx 5 -pady 4
pack .main.toolbar.options -side left -padx 5 -pady 4
pack .main.toolbar.quit -side right -padx 5 -pady 4
pack .main.toolbar.capture -side right -padx 5 -pady 4
pack .main.toolbar -side bottom -fill x

pack .main -fill both -expand 1

# ----------------------------
# Position window and update background offset
# ----------------------------
proc updateBgOffset {} {
    global S screenW screenH sizeVar

    # Get window position on screen
    set wx [winfo rootx .main.c]
    set wy [winfo rooty .main.c]
    set cw [winfo width .main.c]
    set ch [winfo height .main.c]

    # Update size display
    set sizeVar "${cw} x ${ch}"

    # Only update image offset if position changed
    if {$wx == $S(lastX) && $wy == $S(lastY)} return
    set S(lastX) $wx
    set S(lastY) $wy

    # Offset the background image so it aligns with the screen
    .main.c coords bg [expr {-$wx}] [expr {-$wy}]
}

# Refresh the root image (for fake mode)
proc doRefresh {} {
    global screenW screenH S
    wm withdraw .
    update
    after 150
    TkX::capture rootimg root 0 0 $screenW $screenH
    set S(lastX) -1  ;# Force offset update
    wm deiconify .
    update idletasks
    after idle updateDisplay
}

# Set display mode: shape (true transparency) or fake (root image)
proc setDisplayMode {mode} {
    global S
    set S(display) $mode
    updateDisplay
}

# Toggle border visibility
proc toggleBorder {} {
    global S
    # Border frames would go here if needed
}

# Update display based on current mode
proc updateDisplay {} {
    global S sizeVar

    # Get canvas position relative to toplevel
    set cx [expr {[winfo rootx .main.c] - [winfo rootx .]}]
    set cy [expr {[winfo rooty .main.c] - [winfo rooty .]}]
    set cw [winfo width .main.c]
    set ch [winfo height .main.c]

    # Update size display
    set sizeVar "${cw} x ${ch}"

    if {$S(display) eq "shape"} {
        # True transparency - cut a hole, hide the image
        .main.c itemconfigure bg -state hidden
        applyShape $cx $cy $cw $ch
    } else {
        # Fake transparency - show offset root image
        TkX::bounding_reset .
        TkX::input_reset .
        .main.c itemconfigure bg -state normal
        updateBgOffset
    }
}

# Apply shape with guard to prevent loops from ShapeNotify
proc applyShape {cx cy cw ch} {
    global S
    if {$S(applyingShape)} return
    set S(applyingShape) 1
    TkX::bounding_hole . $cx $cy $cw $ch
    TkX::input_hole . $cx $cy $cw $ch
    # Reset flag after delay to ignore our own ShapeNotify
    after 50 {set S(applyingShape) 0}
}

# Called by ShapeNotify when shape is reset externally
proc onShapeChange {} {
    global S
    if {$S(display) eq "shape"} {
        updateDisplay
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
    after cancel updateDisplay
    after idle updateDisplay
}

# ----------------------------
# Size entry
# ----------------------------
bind .main.toolbar.size <Return> {
    if {[regexp {(\d+)\s*x\s*(\d+)} $sizeVar -> newW newH]} {
        global TOOLBAR_H region
        set ww $newW
        set wh [expr {$newH + $TOOLBAR_H}]
        set geom [wm geometry .]
        regexp {\+(-?\d+)\+(-?\d+)} $geom -> gx gy
        wm geometry . ${ww}x${wh}+${gx}+${gy}
        .main.c configure -width $newW -height $newH
        dict set region w $newW
        dict set region h $newH
    }
    focus .
}

# ----------------------------
# Capture - recapture live root
# ----------------------------
proc doCapture {} {
    global region outDir configFile screenW screenH TOOLBAR_H

    set ts [clock format [clock seconds] -format "%Y-%m-%d-%H:%M:%S"]
    set out [file join $outDir "screenshot-$ts.png"]

    # Update region from current window position/size
    set x [winfo rootx .main.c]
    set y [winfo rooty .main.c]
    set w [winfo width .main.c]
    set h [winfo height .main.c]
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
    TkX::capture liveroot root 0 0 $screenW $screenH

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
    dict set region x [winfo rootx .main.c]
    dict set region y [winfo rooty .main.c]
    dict set region w [winfo width .main.c]
    dict set region h [winfo height .main.c]
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
after idle updateDisplay

# Watch for shape changes (when compositor/WM resets our shape)
TkX::shape_watch . onShapeChange

# Keep window on top when focus is lost (input passes through to desktop)
bind . <FocusOut> {
    after idle {wm attributes . -topmost 1; raise .}
}

bind . <Return> doCapture
bind . <Escape> doExit
bind . <Key-q> doExit
