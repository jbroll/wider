/* TkX_window.c - Window management */

#include "TkX.h"

int DoMoveResizeWindow(Tcl_Interp *interp, long winId,
                       int x, int y, int w, int h) {
    REQUIRE_DISPLAY(interp, dpy);
    XMoveResizeWindow(dpy, (Window)winId, x, y, w, h);
    XFlush(dpy);
    return TCL_OK;
}

int DoDestroyWindow(Tcl_Interp *interp, long winId) {
    REQUIRE_DISPLAY(interp, dpy);
    XDestroyWindow(dpy, (Window)winId);
    XFlush(dpy);
    return TCL_OK;
}

int DoReparentWindow(Tcl_Interp *interp, long childId,
                     long parentId, int x, int y) {
    REQUIRE_DISPLAY(interp, dpy);
    XReparentWindow(dpy, (Window)childId, (Window)parentId, x, y);
    XMapWindow(dpy, (Window)childId);
    XFlush(dpy);
    return TCL_OK;
}

int DoMoveWindow(Tcl_Interp *interp, long winId, int x, int y, int w, int h) {
    REQUIRE_DISPLAY(interp, dpy);
    Window win = (Window)winId;

    /* Walk up window hierarchy to find frame and get client-to-frame offset */
    int offX, offY;
    Window frame = WalkToFrame(dpy, win, &offX, &offY);

    /* Get _NET_FRAME_EXTENTS from client window */
    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *data = NULL;
    int frameLeft = 0, frameTop = 0;

    if (XGetWindowProperty(dpy, win, Atoms.NET_FRAME_EXTENTS, 0, 4, False,
                           XA_CARDINAL, &actualType, &actualFormat,
                           &nitems, &bytesAfter, &data) == Success
        && data && nitems >= 4) {
        unsigned long *extents = (unsigned long *)data;
        frameLeft = extents[0];
        frameTop = extents[2];
        XFree(data);
    }

    /* Position frame so client window ends up at (x, y).
     * We subtract offX/offY to convert client coords to frame coords.
     * We also subtract frameLeft/frameTop because xfwm4 adds frame extents
     * to XMoveWindow coordinates (the WM interprets them as client position). */
    int frameX = x - offX - frameLeft;
    int frameY = y - offY - frameTop;

    XMoveWindow(dpy, frame, frameX, frameY);
    if (w > 0 && h > 0) {
        /* Resize the client window, not the frame - w,h are client dimensions */
        XResizeWindow(dpy, win, w, h);
    }
    XFlush(dpy);

    return TCL_OK;
}

int DoWindowOffset(Tcl_Interp *interp, long winId) {
    REQUIRE_DISPLAY(interp, dpy);

    int offX, offY;
    WalkToFrame(dpy, (Window)winId, &offX, &offY);

    Tcl_Obj *result = Tcl_NewListObj(0, NULL);
    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(offX));
    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(offY));
    Tcl_SetObjResult(interp, result);
    return TCL_OK;
}

int DoGetActiveWindow(Tcl_Interp *interp) {
    REQUIRE_DISPLAY(interp, dpy);
    Window root = DefaultRootWindow(dpy);

    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *data = NULL;

    Window active = None;
    if (XGetWindowProperty(dpy, root, Atoms.NET_ACTIVE_WINDOW, 0, 1, False,
                           XA_WINDOW, &actualType, &actualFormat,
                           &nitems, &bytesAfter, &data) == Success
        && data && nitems > 0) {
        active = *(Window *)data;
        XFree(data);
    }

    Tcl_SetObjResult(interp, Tcl_ObjPrintf("0x%lx", (unsigned long)active));
    return TCL_OK;
}

int DoSetDesktop(Tcl_Interp *interp, long winId, int desktop) {
    REQUIRE_DISPLAY(interp, dpy);
    SendClientMessage(dpy, (Window)winId, Atoms.NET_WM_DESKTOP,
                      desktop, 2, 0, 0, 0);
    return TCL_OK;
}

int DoWindowState(Tcl_Interp *interp, long winId, const char *action,
                  const char *prop1, const char *prop2) {
    REQUIRE_DISPLAY(interp, dpy);

    int act = 0;
    if (strcmp(action, "add") == 0) act = 1;
    else if (strcmp(action, "toggle") == 0) act = 2;

    Atom atom1 = prop1 && *prop1 ? XInternAtom(dpy, prop1, False) : None;
    Atom atom2 = prop2 && *prop2 ? XInternAtom(dpy, prop2, False) : None;

    SendClientMessage(dpy, (Window)winId, Atoms.NET_WM_STATE,
                      act, atom1, atom2, 2, 0);
    return TCL_OK;
}

int DoSetProperty(Tcl_Interp *interp, long winId,
                  const char *propName, const char *value) {
    REQUIRE_DISPLAY(interp, dpy);

    Atom prop = XInternAtom(dpy, propName, False);
    XChangeProperty(dpy, (Window)winId, prop, XA_STRING, 8, PropModeReplace,
                    (unsigned char *)value, strlen(value));
    XFlush(dpy);
    return TCL_OK;
}

/* Helper for DoMoveId and DoResizeId */
static int DoMoveResizeById(Tcl_Interp *interp, long winId, int action) {
    REQUIRE_DISPLAY(interp, dpy);

    Window root_ret, child_ret;
    int root_x, root_y, win_x, win_y;
    unsigned int mask;
    XQueryPointer(dpy, DefaultRootWindow(dpy), &root_ret, &child_ret,
                  &root_x, &root_y, &win_x, &win_y, &mask);

    Window root = DefaultRootWindow(dpy);
    XEvent ev = {0};
    ev.xclient.type = ClientMessage;
    ev.xclient.message_type = Atoms.NET_WM_MOVERESIZE;
    ev.xclient.display = dpy;
    ev.xclient.window = (Window)winId;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = root_x;
    ev.xclient.data.l[1] = root_y;
    ev.xclient.data.l[2] = action;
    ev.xclient.data.l[3] = Button1;
    ev.xclient.data.l[4] = 1;

    XSendEvent(dpy, root, False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(dpy);

    return TCL_OK;
}

int DoResizeId(Tcl_Interp *interp, long winId, const char *direction) {
    int edge = dir_to_edge(direction);
    if (edge < 0) {
        Tcl_SetResult(interp, "invalid direction: use nw north ne east se south sw west", TCL_STATIC);
        return TCL_ERROR;
    }
    return DoMoveResizeById(interp, winId, edge);
}

int DoMoveId(Tcl_Interp *interp, long winId) {
    return DoMoveResizeById(interp, winId, NET_WM_MOVERESIZE_MOVE);
}

int DoActivateId(Tcl_Interp *interp, long winId) {
    REQUIRE_DISPLAY(interp, dpy);
    SendClientMessage(dpy, (Window)winId, Atoms.NET_ACTIVE_WINDOW,
                      1, CurrentTime, 0, 0, 0);
    return TCL_OK;
}
