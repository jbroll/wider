/* TkX_csd.c - Client-side decorations, WM move/resize */

#include "TkX.h"

static int DoMoveResize(Tcl_Interp *interp, const char *winPath, int action) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    Atom moveresize = XInternAtom(wi.dpy, "_NET_WM_MOVERESIZE", False);

    XEvent ev = {0};
    ev.xclient.type = ClientMessage;
    ev.xclient.message_type = moveresize;
    ev.xclient.display = wi.dpy;
    ev.xclient.window = wi.tkWin;
    ev.xclient.format = 32;
    ev.xclient.data.l[2] = action;
    ev.xclient.data.l[3] = Button1;

    XSendEvent(wi.dpy, DefaultRootWindow(wi.dpy), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(wi.dpy);

    return TCL_OK;
}

int DoNodecor(Tcl_Interp *interp, const char *winPath) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    Atom prop = XInternAtom(wi.dpy, "_MOTIF_WM_HINTS", False);

    MotifWmHints hints = {0};
    hints.flags = MWM_HINTS_DECORATIONS;
    hints.decorations = 0;

    XChangeProperty(wi.dpy, wi.tkWin, prop, prop, 32, PropModeReplace,
                    (unsigned char *)&hints, 5);
    XFlush(wi.dpy);

    return TCL_OK;
}

int DoMove(Tcl_Interp *interp, const char *winPath) {
    return DoMoveResize(interp, winPath, NET_WM_MOVERESIZE_MOVE);
}

int DoResize(Tcl_Interp *interp, const char *winPath, const char *direction) {
    int edge = dir_to_edge(direction);
    if (edge < 0) {
        Tcl_SetResult(interp, "invalid direction: use nw north ne east se south sw west", TCL_STATIC);
        return TCL_ERROR;
    }
    return DoMoveResize(interp, winPath, edge);
}
