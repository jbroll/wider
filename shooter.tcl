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
# Overlay - darken areas outside selection
# ----------------------------
# We'll draw 4 rectangles around the selection area with stipple pattern
# to simulate darkening

proc updateOverlay {x1 y1 x2 y2} {
    global screenW screenH
    .c delete overlay

    # Ensure coords are ordered
    if {$x1 > $x2} { set t $x1; set x1 $x2; set x2 $t }
    if {$y1 > $y2} { set t $y1; set y1 $y2; set y2 $t }

    # Top overlay
    .c create rectangle 0 0 $screenW $y1 \
        -fill black -stipple gray50 -outline "" -tags overlay
    # Bottom overlay
    .c create rectangle 0 $y2 $screenW $screenH \
        -fill black -stipple gray50 -outline "" -tags overlay
    # Left overlay
    .c create rectangle 0 $y1 $x1 $y2 \
        -fill black -stipple gray50 -outline "" -tags overlay
    # Right overlay
    .c create rectangle $x2 $y1 $screenW $y2 \
        -fill black -stipple gray50 -outline "" -tags overlay
}

# ----------------------------
# Geometry helpers
# ----------------------------
proc normalize {x y w h} {
    list $x $y [expr {$x+$w}] [expr {$y+$h}]
}

proc drawHandles {x1 y1 x2 y2} {
    .c delete handle
    foreach {hx hy corner} [list \
        $x1 $y1 tl \
        $x2 $y1 tr \
        $x1 $y2 bl \
        $x2 $y2 br] {
        .c create rectangle \
            [expr {$hx-8}] [expr {$hy-8}] \
            [expr {$hx+8}] [expr {$hy+8}] \
            -fill white -outline black -width 2 -tags [list handle $corner]
    }
}

proc updateUI {x1 y1 x2 y2} {
    updateOverlay $x1 $y1 $x2 $y2
    .c coords sel $x1 $y1 $x2 $y2
    drawHandles $x1 $y1 $x2 $y2
    # Ensure selection is above overlay
    .c raise sel
    .c raise handle
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
    button .p.b.cancel -text Cancel -command exit
    pack .p.b.ok .p.b.cancel -side left -padx 10
    pack .p.b

    bind .p <Return> [list doSave cropped $out]
    bind .p <Escape> exit
    focus -force .p
}

proc doSave {imgname out} {
    global region configFile

    $imgname write $out -format png

    set f [open $configFile w]
    puts $f $region
    close $f
    exit
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
bind .c <Escape> exit
bind .c <Key-q> exit
