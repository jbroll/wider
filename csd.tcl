# ----------------------------------------------------------------------
# csd.tcl  -- Minimal GTK-style Client-Side Decorations for Tk (X11)
#
# Provides:
#   csd::nodectk  <window>
#   csd::move     <window>
#   csd::resize   <window> <direction>
#
# Directions: north south east west nw ne sw se
#
# Requires: Tk, critcl, X11
# ----------------------------------------------------------------------

package require Tk
package require critcl

namespace eval csd {}

# ----------------------------------------------------------------------
# Embedded C code
# ----------------------------------------------------------------------

critcl::ccode {
#include <tk.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <string.h>

/* -------- Motif WM hints -------------------------------------------- */

typedef struct {
    unsigned long flags;
    unsigned long functions;
    unsigned long decorations;
    long          input_mode;
    unsigned long status;
} MotifWmHints;

#define MWM_HINTS_DECORATIONS (1L << 1)

/* -------- EWMH resize directions ------------------------------------ */
/*
 * Values per _NET_WM_MOVERESIZE specification
 */
static int
dir_to_edge(const char *dir)
{
    if (!strcmp(dir, "nw"))    return 0;
    if (!strcmp(dir, "north")) return 1;
    if (!strcmp(dir, "ne"))    return 2;
    if (!strcmp(dir, "east"))  return 3;
    if (!strcmp(dir, "se"))    return 4;
    if (!strcmp(dir, "south")) return 5;
    if (!strcmp(dir, "sw"))    return 6;
    if (!strcmp(dir, "west"))  return 7;
    return -1;
}
}

# ----------------------------------------------------------------------
# csd::nodectk -- suppress server-side decorations (managed window)
# ----------------------------------------------------------------------

critcl::ccommand csd::nodectk {clientData interp objc objv} {
    if (objc != 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "window");
        return TCL_ERROR;
    }

    Tk_Window tkwin = Tk_NameToWindow(
        interp,
        Tcl_GetString(objv[1]),
        Tk_MainWindow(interp)
    );
    if (!tkwin) return TCL_ERROR;

    Display *dpy = Tk_Display(tkwin);
    Window win   = Tk_WindowId(tkwin);

    Atom prop = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);

    MotifWmHints hints;
    memset(&hints, 0, sizeof(hints));
    hints.flags = MWM_HINTS_DECORATIONS;
    hints.decorations = 0;

    XChangeProperty(
        dpy,
        win,
        prop,
        prop,
        32,
        PropModeReplace,
        (unsigned char *)&hints,
        5
    );

    XFlush(dpy);
    return TCL_OK;
}

# ----------------------------------------------------------------------
# csd::move -- initiate WM-controlled window move (GTK-style)
# ----------------------------------------------------------------------

critcl::ccommand csd::move {clientData interp objc objv} {
    if (objc != 2) {
        Tcl_WrongNumArgs(interp, 1, objv, "window");
        return TCL_ERROR;
    }

    Tk_Window tkwin = Tk_NameToWindow(
        interp,
        Tcl_GetString(objv[1]),
        Tk_MainWindow(interp)
    );
    if (!tkwin) return TCL_ERROR;

    Display *dpy = Tk_Display(tkwin);
    Window win   = Tk_WindowId(tkwin);

    Atom moveresize = XInternAtom(dpy, "_NET_WM_MOVERESIZE", False);

    XEvent ev;
    memset(&ev, 0, sizeof(ev));

    ev.xclient.type = ClientMessage;
    ev.xclient.message_type = moveresize;
    ev.xclient.display = dpy;
    ev.xclient.window = win;
    ev.xclient.format = 32;

    ev.xclient.data.l[0] = 0;        /* root X (unused) */
    ev.xclient.data.l[1] = 0;        /* root Y (unused) */
    ev.xclient.data.l[2] = 8;        /* MOVE */
    ev.xclient.data.l[3] = Button1;  /* button */
    ev.xclient.data.l[4] = 0;

    XSendEvent(
        dpy,
        DefaultRootWindow(dpy),
        False,
        SubstructureRedirectMask | SubstructureNotifyMask,
        &ev
    );

    XFlush(dpy);
    return TCL_OK;
}

# ----------------------------------------------------------------------
# csd::resize -- initiate WM-controlled resize (GTK-style)
# ----------------------------------------------------------------------

critcl::ccommand csd::resize {clientData interp objc objv} {
    if (objc != 3) {
        Tcl_WrongNumArgs(interp, 1, objv, "window direction");
        return TCL_ERROR;
    }

    int edge = dir_to_edge(Tcl_GetString(objv[2]));
    if (edge < 0) {
        Tcl_SetResult(interp, "invalid direction", TCL_STATIC);
        return TCL_ERROR;
    }

    Tk_Window tkwin = Tk_NameToWindow(
        interp,
        Tcl_GetString(objv[1]),
        Tk_MainWindow(interp)
    );
    if (!tkwin) return TCL_ERROR;

    Display *dpy = Tk_Display(tkwin);
    Window win   = Tk_WindowId(tkwin);

    Atom moveresize = XInternAtom(dpy, "_NET_WM_MOVERESIZE", False);

    XEvent ev;
    memset(&ev, 0, sizeof(ev));

    ev.xclient.type = ClientMessage;
    ev.xclient.message_type = moveresize;
    ev.xclient.display = dpy;
    ev.xclient.window = win;
    ev.xclient.format = 32;

    ev.xclient.data.l[0] = 0;
    ev.xclient.data.l[1] = 0;
    ev.xclient.data.l[2] = edge;
    ev.xclient.data.l[3] = Button1;
    ev.xclient.data.l[4] = 0;

    XSendEvent(
        dpy,
        DefaultRootWindow(dpy),
        False,
        SubstructureRedirectMask | SubstructureNotifyMask,
        &ev
    );

    XFlush(dpy);
    return TCL_OK;
}

package provide csd 0.1
