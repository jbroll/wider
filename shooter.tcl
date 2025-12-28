#!/usr/bin/env tclsh
#
# shooter.tcl - Screenshot region capture using fake transparency
#
# Uses xgetimage to capture root window as background (fake transparency)
# Uses overrideredirect to bypass window manager (no decorations)
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
# State
# ----------------------------
array set S {
    rect ""
    mode ""
    hx   0
    hy   0
    ax   0
    ay   0
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
wm overrideredirect . 1

# Capture the root window BEFORE showing our window
image create photo rootimg
xgetimage::capture rootimg root 0 0 $screenW $screenH

# Create canvas with root image as background
canvas .c -highlightthickness 0 -width $screenW -height $screenH
.c create image 0 0 -anchor nw -image rootimg -tags bg

pack .c -fill both -expand 1

# Set geometry (overrideredirect bypasses WM entirely)
wm geometry . ${screenW}x${screenH}+0+0
update idletasks

# ----------------------------
# Overlay - stippled rectangles for darkening
# ----------------------------
.c create rectangle 0 0 0 0 -fill black -stipple gray50 -outline "" -tags {overlay otop}
.c create rectangle 0 0 0 0 -fill black -stipple gray50 -outline "" -tags {overlay obot}
.c create rectangle 0 0 0 0 -fill black -stipple gray50 -outline "" -tags {overlay oleft}
.c create rectangle 0 0 0 0 -fill black -stipple gray50 -outline "" -tags {overlay oright}

# ----------------------------
# Handles (created once, coords updated)
# ----------------------------
foreach corner {tl tr bl br} {
    .c create rectangle 0 0 0 0 -fill white -outline black -width 2 -tags [list handle $corner]
}

# ----------------------------
# Size entry widget embedded in canvas
# ----------------------------
set sizeVar "500 x 400"
frame .c.sizebox -bg black -padx 2 -pady 2
entry .c.sizebox.e -textvariable sizeVar -font {Helvetica 18 bold} \
    -width 12 -justify center -bg white -relief flat
pack .c.sizebox.e
set S(sizewin) [.c create window 0 0 -window .c.sizebox -tags sizeentry]

# Apply size from entry when Return is pressed in the entry
bind .c.sizebox.e <Return> {
    if {[regexp {(\d+)\s*x\s*(\d+)} $sizeVar -> newW newH]} {
        lassign [.c coords $S(rect)] x1 y1 x2 y2
        # Keep top-left corner, adjust bottom-right
        set nx1 [expr {min($x1,$x2)}]
        set ny1 [expr {min($y1,$y2)}]
        set nx2 [expr {$nx1 + $newW}]
        set ny2 [expr {$ny1 + $newH}]
        .c coords $S(rect) $nx1 $ny1 $nx2 $ny2
        updateUI $nx1 $ny1 $nx2 $ny2
        # Update region
        dict set region x [expr {int($nx1)}]
        dict set region y [expr {int($ny1)}]
        dict set region w $newW
        dict set region h $newH
    }
    focus .c
}

# Escape in entry returns focus to canvas
bind .c.sizebox.e <Escape> {focus .c}

# ----------------------------
# Geometry helpers
# ----------------------------
proc normalize {x y w h} {
    list $x $y [expr {$x+$w}] [expr {$y+$h}]
}

proc updateOverlay {x1 y1 x2 y2} {
    global screenW screenH
    # Ensure coords are ordered
    if {$x1 > $x2} { set t $x1; set x1 $x2; set x2 $t }
    if {$y1 > $y2} { set t $y1; set y1 $y2; set y2 $t }

    .c coords otop   0 0 $screenW $y1
    .c coords obot   0 $y2 $screenW $screenH
    .c coords oleft  0 $y1 $x1 $y2
    .c coords oright $x2 $y1 $screenW $y2
}

proc updateHandles {x1 y1 x2 y2} {
    .c coords tl [expr {$x1-8}] [expr {$y1-8}] [expr {$x1+8}] [expr {$y1+8}]
    .c coords tr [expr {$x2-8}] [expr {$y1-8}] [expr {$x2+8}] [expr {$y1+8}]
    .c coords bl [expr {$x1-8}] [expr {$y2-8}] [expr {$x1+8}] [expr {$y2+8}]
    .c coords br [expr {$x2-8}] [expr {$y2-8}] [expr {$x2+8}] [expr {$y2+8}]
}

proc updateUI {x1 y1 x2 y2} {
    global S sizeVar

    updateOverlay $x1 $y1 $x2 $y2
    .c coords sel $x1 $y1 $x2 $y2
    updateHandles $x1 $y1 $x2 $y2

    # Calculate dimensions and update entry
    set w [expr {int(abs($x2-$x1))}]
    set h [expr {int(abs($y2-$y1))}]
    set sizeVar "${w} x ${h}"

    # Position entry in center of selection
    set cx [expr {($x1+$x2)/2}]
    set cy [expr {($y1+$y2)/2}]
    .c coords $S(sizewin) $cx $cy

    # Ensure proper stacking order
    .c raise sel
    .c raise handle
    .c raise sizeentry
}

# ----------------------------
# Initial rectangle
# ----------------------------
lassign [normalize \
    [dict get $region x] \
    [dict get $region y] \
    [dict get $region w] \
    [dict get $region h]] x1 y1 x2 y2

set S(rect) [.c create rectangle $x1 $y1 $x2 $y2 \
    -outline white -width 3 -tags sel]

updateUI $x1 $y1 $x2 $y2

# ----------------------------
# Mouse logic
# ----------------------------
proc insideSelection {px py} {
    global S
    if {$S(rect) eq ""} { return 0 }
    lassign [.c coords $S(rect)] x1 y1 x2 y2
    if {$x1 > $x2} { set t $x1; set x1 $x2; set x2 $t }
    if {$y1 > $y2} { set t $y1; set y1 $y2; set y2 $t }
    expr {$px >= $x1 && $px <= $x2 && $py >= $y1 && $py <= $y2}
}

bind .c <ButtonPress-1> {
    set S(hx) %x
    set S(hy) %y
    set id [.c find withtag current]
    set tags [.c gettags $id]

    if {[lsearch $tags handle] >= 0} {
        set S(mode) resize
        lassign [.c coords $S(rect)] x1 y1 x2 y2
        if {[lsearch $tags tl] >= 0} {
            set S(ax) $x2; set S(ay) $y2
        } elseif {[lsearch $tags tr] >= 0} {
            set S(ax) $x1; set S(ay) $y2
        } elseif {[lsearch $tags bl] >= 0} {
            set S(ax) $x2; set S(ay) $y1
        } elseif {[lsearch $tags br] >= 0} {
            set S(ax) $x1; set S(ay) $y1
        }
    } elseif {[insideSelection %x %y]} {
        set S(mode) move
    } else {
        # Click outside selection/handles - do nothing
        set S(mode) ""
    }
}

bind .c <B1-Motion> {
    if {$S(mode) eq ""} return

    set dx [expr {%x - $S(hx)}]
    set dy [expr {%y - $S(hy)}]

    switch $S(mode) {
        resize {
            .c coords $S(rect) $S(ax) $S(ay) %x %y
        }
        move {
            .c move $S(rect) $dx $dy
        }
    }

    set S(hx) %x
    set S(hy) %y

    lassign [.c coords $S(rect)] x1 y1 x2 y2
    updateUI $x1 $y1 $x2 $y2
}

bind .c <ButtonRelease-1> {
    lassign [.c coords $S(rect)] x1 y1 x2 y2
    set x [expr {int(min($x1,$x2))}]
    set y [expr {int(min($y1,$y2))}]
    set w [expr {int(abs($x2-$x1))}]
    set h [expr {int(abs($y2-$y1))}]
    dict set region x $x
    dict set region y $y
    dict set region w $w
    dict set region h $h
}

# ----------------------------
# Capture - recapture live root
# ----------------------------
proc doCapture {} {
    global region outDir configFile screenW screenH

    set ts [clock format [clock seconds] -format "%Y-%m-%d-%H:%M:%S"]
    set out [file join $outDir "screenshot-$ts.png"]

    # Hide our window
    wm withdraw .
    update
    after 150

    # Recapture the live root window
    image create photo liveroot
    xgetimage::capture liveroot root 0 0 $screenW $screenH

    # Crop to selection region
    set x [dict get $region x]
    set y [dict get $region y]
    set w [dict get $region w]
    set h [dict get $region h]

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
tkwait visibility .c
focus -force .c
grab set -global .c

bind .c <Return> doCapture
bind .c <Escape> doExit
bind .c <Key-q> doExit
