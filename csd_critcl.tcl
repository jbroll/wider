# csd_critcl.tcl - Minimal GTK-style Client-Side Decorations for Tk (X11)
#
# Provides:
#   csd::nodecor <window>              - Remove window decorations
#   csd::move    <window>              - Initiate WM-controlled move
#   csd::resize  <window> <direction>  - Initiate WM-controlled resize
#
# Directions: north south east west nw ne sw se
#
# Build: critcl -pkg csd_critcl.tcl

package require Tcl 8.6
package require critcl 3.2

critcl::tcl 8.6
critcl::tk

critcl::clibraries -lX11

critcl::ccode {
    #include <X11/Xlib.h>
    #include <X11/Xatom.h>
    #include <string.h>

    /* Motif WM hints structure */
    typedef struct {
        unsigned long flags;
        unsigned long functions;
        unsigned long decorations;
        long          input_mode;
        unsigned long status;
    } MotifWmHints;

    #define MWM_HINTS_DECORATIONS (1L << 1)

    /* EWMH resize directions per _NET_WM_MOVERESIZE specification */
    static int dir_to_edge(const char *dir) {
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

    static int DoNodecor(Tcl_Interp *interp, const char *winPath) {
        Tk_Window tkwin = Tk_NameToWindow(interp, winPath, Tk_MainWindow(interp));
        if (!tkwin) return TCL_ERROR;

        Display *dpy = Tk_Display(tkwin);
        Window win = Tk_WindowId(tkwin);

        Atom prop = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);

        MotifWmHints hints;
        memset(&hints, 0, sizeof(hints));
        hints.flags = MWM_HINTS_DECORATIONS;
        hints.decorations = 0;

        XChangeProperty(dpy, win, prop, prop, 32, PropModeReplace,
                        (unsigned char *)&hints, 5);
        XFlush(dpy);

        return TCL_OK;
    }

    static int DoMove(Tcl_Interp *interp, const char *winPath) {
        Tk_Window tkwin = Tk_NameToWindow(interp, winPath, Tk_MainWindow(interp));
        if (!tkwin) return TCL_ERROR;

        Display *dpy = Tk_Display(tkwin);
        Window win = Tk_WindowId(tkwin);

        Atom moveresize = XInternAtom(dpy, "_NET_WM_MOVERESIZE", False);

        XEvent ev;
        memset(&ev, 0, sizeof(ev));
        ev.xclient.type = ClientMessage;
        ev.xclient.message_type = moveresize;
        ev.xclient.display = dpy;
        ev.xclient.window = win;
        ev.xclient.format = 32;
        ev.xclient.data.l[0] = 0;       /* root X (unused) */
        ev.xclient.data.l[1] = 0;       /* root Y (unused) */
        ev.xclient.data.l[2] = 8;       /* _NET_WM_MOVERESIZE_MOVE */
        ev.xclient.data.l[3] = Button1;
        ev.xclient.data.l[4] = 0;

        XSendEvent(dpy, DefaultRootWindow(dpy), False,
                   SubstructureRedirectMask | SubstructureNotifyMask, &ev);
        XFlush(dpy);

        return TCL_OK;
    }

    static int DoResize(Tcl_Interp *interp, const char *winPath, const char *direction) {
        int edge = dir_to_edge(direction);
        if (edge < 0) {
            Tcl_SetResult(interp, "invalid direction: use nw north ne east se south sw west", TCL_STATIC);
            return TCL_ERROR;
        }

        Tk_Window tkwin = Tk_NameToWindow(interp, winPath, Tk_MainWindow(interp));
        if (!tkwin) return TCL_ERROR;

        Display *dpy = Tk_Display(tkwin);
        Window win = Tk_WindowId(tkwin);

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

        XSendEvent(dpy, DefaultRootWindow(dpy), False,
                   SubstructureRedirectMask | SubstructureNotifyMask, &ev);
        XFlush(dpy);

        return TCL_OK;
    }
}

critcl::cproc csd::nodecor {
    Tcl_Interp* interp
    char* window
} ok {
    return DoNodecor(interp, window);
}

critcl::cproc csd::move {
    Tcl_Interp* interp
    char* window
} ok {
    return DoMove(interp, window);
}

critcl::cproc csd::resize {
    Tcl_Interp* interp
    char* window
    char* direction
} ok {
    return DoResize(interp, window, direction);
}

package provide csd 0.2
