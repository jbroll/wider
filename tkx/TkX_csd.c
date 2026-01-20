/* TkX_csd.c - Client-side decorations, WM move/resize */

#include "TkX.h"

static int DoMoveResize(Tcl_Interp *interp, const char *winPath, int action) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    SendClientMessage(wi.dpy, wi.tkWin, Atoms.NET_WM_MOVERESIZE,
                      0, 0, action, Button1, 0);
    return TCL_OK;
}

int DoNodecor(Tcl_Interp *interp, const char *winPath) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    MotifWmHints hints = {0};
    hints.flags = MWM_HINTS_DECORATIONS;
    hints.decorations = 0;

    XChangeProperty(wi.dpy, wi.tkWin, Atoms.MOTIF_WM_HINTS,
                    Atoms.MOTIF_WM_HINTS, 32, PropModeReplace,
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
