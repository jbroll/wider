#!/usr/bin/env tclsh
package require Tk

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
# UI - fullscreen window (no overrideredirect)
# ----------------------------
wm title . "Screenshot - Enter to capture, Escape to cancel"
wm attributes . -topmost 1

canvas .c -bg black -highlightthickness 0
pack .c -fill both -expand 1

# Maximize window
update idletasks
wm geometry . [winfo screenwidth .]x[winfo screenheight .]+0+0

# Apply alpha AFTER window is visible (2 second delay like working test)
after 500 {wm attributes . -alpha 0.25}

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
            [expr {$hx-10}] [expr {$hy-10}] \
            [expr {$hx+10}] [expr {$hy+10}] \
            -fill white -outline black -width 2 -tags [list handle $corner]
    }
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

drawHandles $x1 $y1 $x2 $y2

# ----------------------------
# Mouse logic
# ----------------------------
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
    } elseif {[lsearch $tags sel] >= 0} {
        set S(mode) move
    } else {
        set S(mode) new
        .c delete sel handle
        set S(rect) [.c create rectangle %x %y %x %y \
            -outline white -width 3 -tags sel]
        set S(ax) %x
        set S(ay) %y
    }
}

bind .c <B1-Motion> {
    set dx [expr {%x - $S(hx)}]
    set dy [expr {%y - $S(hy)}]

    switch $S(mode) {
        new - resize {
            .c coords $S(rect) $S(ax) $S(ay) %x %y
        }
        move {
            .c move $S(rect) $dx $dy
        }
    }

    set S(hx) %x
    set S(hy) %y

    lassign [.c coords $S(rect)] x1 y1 x2 y2
    drawHandles $x1 $y1 $x2 $y2
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
# Capture
# ----------------------------
proc doCapture {} {
    global region outDir configFile

    set ts [clock format [clock seconds] -format "%Y-%m-%d-%H:%M:%S"]
    set tmp "/tmp/shot.png"
    set out [file join $outDir "screenshot-$ts.png"]

    wm withdraw .
    update
    after 100

    exec scrot -o -a [dict get $region x],[dict get $region y],[dict get $region w],[dict get $region h] $tmp

    image create photo preview -file $tmp

    toplevel .p
    wm title .p "Preview - Enter=Save, Escape=Cancel"
    wm geometry .p +[dict get $region x]+[dict get $region y]
    wm attributes .p -topmost 1

    label .p.i -image preview
    pack .p.i

    frame .p.b
    button .p.b.ok -text Save -command [list doSave $tmp $out]
    button .p.b.cancel -text Cancel -command exit
    pack .p.b.ok .p.b.cancel -side left -padx 10
    pack .p.b

    bind .p <Return> [list doSave $tmp $out]
    bind .p <Escape> exit
    focus -force .p
}

proc doSave {tmp out} {
    global region configFile
    file rename -force $tmp $out
    set f [open $configFile w]
    puts $f $region
    close $f
    exit
}

bind . <Return> doCapture
bind . <Escape> exit
bind . <Key-q> exit

focus -force .
