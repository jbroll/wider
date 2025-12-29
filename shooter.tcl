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

# Resize state (separate from S array for easy [info exists] check)
# When set: {edge startX startY startWinX startWinY startW startH}
# unset when not resizing

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

# Title bar (pack first so it keeps space on resize)
frame .main.titlebar -height $TOOLBAR_H -bg #333333
set cw [dict get $region w]
set ch [dict get $region h]
set sizeVar "${cw} x ${ch}"

# Capture button on left (red like Peek's record)
button .main.titlebar.capture -text "●" -command doCapture \
    -bg #e74c3c -fg white -relief flat -padx 8 -font {Helvetica 14}

# Drag area in middle (expands to fill)
frame .main.titlebar.drag -bg #333333 -height $TOOLBAR_H

# Size display in drag area
label .main.titlebar.drag.size -textvariable sizeVar -font {Helvetica 10} \
    -bg #333333 -fg #888888
pack .main.titlebar.drag.size -expand 1

# Hamburger menu on right
menubutton .main.titlebar.menu -text "☰" -menu .main.titlebar.menu.m \
    -bg #333333 -fg white -relief flat -padx 8 -font {Helvetica 14}
menu .main.titlebar.menu.m -tearoff 0
.main.titlebar.menu.m add command -label "Refresh" -command doRefresh
.main.titlebar.menu.m add separator
.main.titlebar.menu.m add command -label "Set size..." -command {focus .main.titlebar.drag.size}
.main.titlebar.menu.m add separator
.main.titlebar.menu.m add radiobutton -label "Shape (compositor)" \
    -variable S(display) -value "shape" -command {setDisplayMode shape}
.main.titlebar.menu.m add radiobutton -label "Fake transparency" \
    -variable S(display) -value "fake" -command {setDisplayMode fake}

# Close button on far right
button .main.titlebar.close -text "✕" -command doExit \
    -bg #333333 -fg white -relief flat -padx 8 -font {Helvetica 12} \
    -activebackground #e74c3c -activeforeground white

pack .main.titlebar.capture -side left -padx 2 -pady 4
pack .main.titlebar.close -side right -padx 2 -pady 4
pack .main.titlebar.menu -side right -padx 2 -pady 4
pack .main.titlebar.drag -side left -fill both -expand 1 -pady 4
pack .main.titlebar -side top -fill x

# Border frame around canvas (visible edge of capture area)
set BORDER 8
frame .main.border -bg #e74c3c -padx $BORDER -pady $BORDER
canvas .main.border.c -highlightthickness 0 -width $cw -height $ch -bg black
.main.border.c create image 0 0 -anchor nw -image rootimg -tags bg
pack .main.border.c -fill both -expand 1
pack .main.border -side top -fill both -expand 1

pack .main -fill both -expand 1

# ----------------------------
# Window drag bindings (titlebar)
# ----------------------------
bind .main.titlebar.drag <Button-1> {set ::drag_start [list %X %Y [winfo x .] [winfo y .]]}
bind .main.titlebar.drag <B1-Motion> {
    lassign $::drag_start sx sy wx wy
    wm geometry . +[expr {$wx + %X - $sx}]+[expr {$wy + %Y - $sy}]
}


# ----------------------------
# Position window and update background offset
# ----------------------------
proc updateBgOffset {} {
    global S screenW screenH sizeVar

    # Get window position on screen
    set wx [winfo rootx .main.border.c]
    set wy [winfo rooty .main.border.c]
    set cw [winfo width .main.border.c]
    set ch [winfo height .main.border.c]

    # Update size display
    set sizeVar "${cw} x ${ch}"

    # Only update image offset if position changed
    if {$wx == $S(lastX) && $wy == $S(lastY)} return
    set S(lastX) $wx
    set S(lastY) $wy

    # Offset the background image so it aligns with the screen
    .main.border.c coords bg [expr {-$wx}] [expr {-$wy}]
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
    set cx [expr {[winfo rootx .main.border.c] - [winfo rootx .]}]
    set cy [expr {[winfo rooty .main.border.c] - [winfo rooty .]}]
    set cw [winfo width .main.border.c]
    set ch [winfo height .main.border.c]

    # Update size display
    set sizeVar "${cw} x ${ch}"

    if {$S(display) eq "shape"} {
        # True transparency - cut a hole, hide the image
        .main.border.c itemconfigure bg -state hidden
        applyShape $cx $cy $cw $ch
    } else {
        # Fake transparency - show offset root image
        TkX::bounding_reset .
        TkX::input_reset .
        .main.border.c itemconfigure bg -state normal
        updateBgOffset
    }
}

# Apply shape with guard to prevent loops from ShapeNotify
proc applyShape {cx cy cw ch} {
    global S
    if {$S(applyingShape) || [info exists ::resizing]} return
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

# Initial geometry from saved region (add border and toolbar)
set wx [dict get $region x]
set wy [dict get $region y]
set ww [expr {[dict get $region w] + 2*$BORDER}]
set wh [expr {[dict get $region h] + 2*$BORDER + $TOOLBAR_H}]
wm geometry . ${ww}x${wh}+${wx}+${wy}

# ----------------------------
# Track window movement via Configure events
# ----------------------------
bind . <Configure> {
    # Skip updates during resize - we'll update once at the end
    if {![info exists ::resizing]} {
        after cancel updateDisplay
        after idle updateDisplay
    }
}

# ----------------------------
# Resize handling
# ----------------------------
set EDGE_SIZE 8   ;# Pixels from edge to trigger resize (matches BORDER)
set CORNER_SIZE 16 ;# Larger area for corners (easier to grab)

# Detect which resize edge the cursor is near
proc getResizeEdge {x y} {
    global EDGE_SIZE CORNER_SIZE
    set w [winfo width .]
    set h [winfo height .]

    # Check corners first (larger area)
    set corner_left   [expr {$x < $CORNER_SIZE}]
    set corner_right  [expr {$x >= $w - $CORNER_SIZE}]
    set corner_top    [expr {$y < $CORNER_SIZE}]
    set corner_bottom [expr {$y >= $h - $CORNER_SIZE}]

    # Corners (use larger CORNER_SIZE)
    if {$corner_top && $corner_left}     {return "nw"}
    if {$corner_top && $corner_right}    {return "ne"}
    if {$corner_bottom && $corner_left}  {return "sw"}
    if {$corner_bottom && $corner_right} {return "se"}

    # Edges (use smaller EDGE_SIZE)
    set left   [expr {$x < $EDGE_SIZE}]
    set right  [expr {$x >= $w - $EDGE_SIZE}]
    set top    [expr {$y < $EDGE_SIZE}]
    set bottom [expr {$y >= $h - $EDGE_SIZE}]

    if {$left}   {return "w"}
    if {$right}  {return "e"}
    if {$top}    {return "n"}
    if {$bottom} {return "s"}
    return ""
}

# Map edge to cursor
proc edgeToCursor {edge} {
    switch $edge {
        n  {return "top_side"}
        s  {return "bottom_side"}
        e  {return "right_side"}
        w  {return "left_side"}
        nw {return "top_left_corner"}
        ne {return "top_right_corner"}
        sw {return "bottom_left_corner"}
        se {return "bottom_right_corner"}
        default {return ""}
    }
}

# Update cursor on mouse motion (need to handle events on child widgets too)
proc handleMotion {x y} {
    if {![info exists ::resizing]} {
        set edge [getResizeEdge $x $y]
        set cursor [edgeToCursor $edge]
        . configure -cursor $cursor
    }
}

proc handleButtonPress {x y X Y} {
    set edge [getResizeEdge $x $y]
    if {$edge ne ""} {
        set ::resizing [list $edge $X $Y [winfo x .] [winfo y .] [winfo width .] [winfo height .]]
        grab set .
        return 1
    }
    return 0
}

# Bind to toplevel
bind . <Motion> {handleMotion %x %y}
bind . <Button-1> {handleButtonPress %x %y %X %Y}

# Bind to border frame for bottom/side edges (use pointer position for reliability)
bind .main.border <Motion> {
    set x [expr {[winfo pointerx .] - [winfo rootx .]}]
    set y [expr {[winfo pointery .] - [winfo rooty .]}]
    handleMotion $x $y
}
bind .main.border <Button-1> {
    set x [expr {[winfo pointerx .] - [winfo rootx .]}]
    set y [expr {[winfo pointery .] - [winfo rooty .]}]
    if {[handleButtonPress $x $y %X %Y]} break
}

# Perform resize during drag
bind . <B1-Motion> {
    if {[info exists ::resizing]} {
        lassign $::resizing edge sx sy wx wy sw sh
        set dx [expr {%X - $sx}]
        set dy [expr {%Y - $sy}]

        # Calculate new geometry based on edge
        set nx $wx
        set ny $wy
        set nw $sw
        set nh $sh

        switch $edge {
            n {
                set ny [expr {$wy + $dy}]
                set nh [expr {$sh - $dy}]
            }
            s {
                set nh [expr {$sh + $dy}]
            }
            w {
                set nx [expr {$wx + $dx}]
                set nw [expr {$sw - $dx}]
            }
            e {
                set nw [expr {$sw + $dx}]
            }
            nw {
                set nx [expr {$wx + $dx}]
                set ny [expr {$wy + $dy}]
                set nw [expr {$sw - $dx}]
                set nh [expr {$sh - $dy}]
            }
            ne {
                set ny [expr {$wy + $dy}]
                set nw [expr {$sw + $dx}]
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

        # Enforce minimum size
        if {$nw < 100} {set nw 100}
        if {$nh < 100} {set nh 100}

        # Apply geometry
        wm geometry . ${nw}x${nh}+${nx}+${ny}
        update idletasks

        # Update shape immediately during resize (keep guard active)
        set S(applyingShape) 1
        set cx [expr {[winfo rootx .main.border.c] - [winfo rootx .]}]
        set cy [expr {[winfo rooty .main.border.c] - [winfo rooty .]}]
        set cw [winfo width .main.border.c]
        set ch [winfo height .main.border.c]
        TkX::bounding_hole . $cx $cy $cw $ch
        TkX::input_hole . $cx $cy $cw $ch

        # Update size display
        set ::sizeVar "${cw} x ${ch}"
    }
}

# End resize on button release
bind . <ButtonRelease-1> {
    if {[info exists ::resizing]} {
        grab release .
        unset ::resizing
        . configure -cursor ""
        # Reset shape guard after a delay
        after 100 {set S(applyingShape) 0}
    }
}


# ----------------------------
# Capture - recapture live root
# ----------------------------
proc doCapture {} {
    global region outDir configFile screenW screenH TOOLBAR_H

    set ts [clock format [clock seconds] -format "%Y-%m-%d-%H:%M:%S"]
    set out [file join $outDir "screenshot-$ts.png"]

    # Canvas screen position for cropping
    set x [winfo rootx .main.border.c]
    set y [winfo rooty .main.border.c]
    set w [winfo width .main.border.c]
    set h [winfo height .main.border.c]

    # Get actual position and subtract frame offset to get geometry value
    set actual_x [winfo x .]
    set actual_y [winfo y .]
    lassign [TkX::frame_offset .] off_x off_y
    dict set region x [expr {$actual_x - $off_x}]
    dict set region y [expr {$actual_y - $off_y}]
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
    # Get actual position and subtract frame offset to get geometry value
    set actual_x [winfo x .]
    set actual_y [winfo y .]
    lassign [TkX::frame_offset .] off_x off_y

    dict set region x [expr {$actual_x - $off_x}]
    dict set region y [expr {$actual_y - $off_y}]
    dict set region w [winfo width .main.border.c]
    dict set region h [winfo height .main.border.c]
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
# Use overrideredirect to avoid darkening from compositor
wm overrideredirect . 1
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
