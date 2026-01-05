/* TkX_window.c - Window management */

#include "TkX.h"

int DoMoveResizeWindow(Tcl_Interp *interp, long winId,
                       int x, int y, int w, int h) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)winId;

    XMoveResizeWindow(dpy, win, x, y, w, h);
    XFlush(dpy);
    return TCL_OK;
}

int DoDestroyWindow(Tcl_Interp *interp, long winId) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)winId;

    XDestroyWindow(dpy, win);
    XFlush(dpy);
    return TCL_OK;
}

int DoReparentWindow(Tcl_Interp *interp, long childId,
                     long parentId, int x, int y) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);

    XReparentWindow(dpy, (Window)childId, (Window)parentId, x, y);
    XMapWindow(dpy, (Window)childId);
    XFlush(dpy);
    return TCL_OK;
}

int DoMoveWindow(Tcl_Interp *interp, long winId, int x, int y, int w, int h) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)winId;
    Window root = DefaultRootWindow(dpy);

    /* Walk up window hierarchy to find frame and compute offset */
    int offX = 0, offY = 0;
    Window parent, *children, current = win;
    unsigned int nchildren;
    XWindowAttributes attr;

    while (1) {
        if (!XQueryTree(dpy, current, &root, &parent, &children, &nchildren))
            break;
        if (children) XFree(children);
        if (parent == root) break;

        if (XGetWindowAttributes(dpy, current, &attr)) {
            offX += attr.x;
            offY += attr.y;
        }
        current = parent;
    }

    /* Get _NET_FRAME_EXTENTS from client window (WM sets it there, not on frame) */
    Atom frameExtents = XInternAtom(dpy, "_NET_FRAME_EXTENTS", False);
    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *data = NULL;
    int frameLeft = 0, frameTop = 0;

    if (XGetWindowProperty(dpy, win, frameExtents, 0, 4, False,
                           XA_CARDINAL, &actualType, &actualFormat,
                           &nitems, &bytesAfter, &data) == Success
        && data && nitems >= 4) {
        unsigned long *extents = (unsigned long *)data;
        frameLeft = extents[0];  /* left */
        frameTop = extents[2];   /* top */
        XFree(data);
    }

    /* Subtract offset twice: once for client-to-frame offset, once more
     * to compensate for xfwm4 adding frame extents to move coordinates */
    int frameX = x - offX - frameLeft;
    int frameY = y - offY - frameTop;

    if (w > 0 && h > 0) {
        XMoveResizeWindow(dpy, current, frameX, frameY, w, h);
    } else {
        XMoveWindow(dpy, current, frameX, frameY);
    }
    XFlush(dpy);

    return TCL_OK;
}

int DoWindowOffset(Tcl_Interp *interp, long winId) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)winId;
    Window root = DefaultRootWindow(dpy);

    int offX = 0, offY = 0;
    Window parent, *children;
    unsigned int nchildren;
    XWindowAttributes attr;

    while (1) {
        if (!XQueryTree(dpy, win, &root, &parent, &children, &nchildren)) {
            break;
        }
        if (children) XFree(children);
        if (parent == root) break;

        if (XGetWindowAttributes(dpy, win, &attr)) {
            offX += attr.x;
            offY += attr.y;
        }
        win = parent;
    }

    Tcl_Obj *result = Tcl_NewListObj(0, NULL);
    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(offX));
    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(offY));
    Tcl_SetObjResult(interp, result);
    return TCL_OK;
}

int DoGetActiveWindow(Tcl_Interp *interp) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window root = DefaultRootWindow(dpy);

    Atom activeAtom = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);
    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytesAfter;
    unsigned char *data = NULL;

    Window active = None;
    if (XGetWindowProperty(dpy, root, activeAtom, 0, 1, False,
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
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window root = DefaultRootWindow(dpy);
    Window win = (Window)winId;

    Atom wmDesktop = XInternAtom(dpy, "_NET_WM_DESKTOP", False);

    XEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.xclient.type = ClientMessage;
    ev.xclient.window = win;
    ev.xclient.message_type = wmDesktop;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = desktop;
    ev.xclient.data.l[1] = 2;

    XSendEvent(dpy, root, False,
               SubstructureNotifyMask | SubstructureRedirectMask, &ev);
    XFlush(dpy);
    return TCL_OK;
}

int DoWindowState(Tcl_Interp *interp, long winId, const char *action,
                  const char *prop1, const char *prop2) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window root = DefaultRootWindow(dpy);
    Window win = (Window)winId;

    int act = 0;
    if (strcmp(action, "add") == 0) act = 1;
    else if (strcmp(action, "toggle") == 0) act = 2;

    Atom wmState = XInternAtom(dpy, "_NET_WM_STATE", False);
    Atom atom1 = prop1 && *prop1 ? XInternAtom(dpy, prop1, False) : None;
    Atom atom2 = prop2 && *prop2 ? XInternAtom(dpy, prop2, False) : None;

    XEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.xclient.type = ClientMessage;
    ev.xclient.window = win;
    ev.xclient.message_type = wmState;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = act;
    ev.xclient.data.l[1] = atom1;
    ev.xclient.data.l[2] = atom2;
    ev.xclient.data.l[3] = 2;

    XSendEvent(dpy, root, False,
               SubstructureNotifyMask | SubstructureRedirectMask, &ev);
    XFlush(dpy);
    return TCL_OK;
}

int DoSetProperty(Tcl_Interp *interp, long winId,
                  const char *propName, const char *value) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)winId;

    Atom prop = XInternAtom(dpy, propName, False);
    XChangeProperty(dpy, win, prop, XA_STRING, 8, PropModeReplace,
                    (unsigned char *)value, strlen(value));
    XFlush(dpy);
    return TCL_OK;
}

int DoResizeId(Tcl_Interp *interp, long winId, const char *direction) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)winId;

    int edge = dir_to_edge(direction);
    if (edge < 0) {
        Tcl_SetResult(interp, "invalid direction: use nw north ne east se south sw west", TCL_STATIC);
        return TCL_ERROR;
    }

    Window root_ret, child_ret;
    int root_x, root_y, win_x, win_y;
    unsigned int mask;
    XQueryPointer(dpy, DefaultRootWindow(dpy), &root_ret, &child_ret,
                  &root_x, &root_y, &win_x, &win_y, &mask);

    Atom moveresize = XInternAtom(dpy, "_NET_WM_MOVERESIZE", False);

    XEvent ev = {0};
    ev.xclient.type = ClientMessage;
    ev.xclient.message_type = moveresize;
    ev.xclient.display = dpy;
    ev.xclient.window = win;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = root_x;
    ev.xclient.data.l[1] = root_y;
    ev.xclient.data.l[2] = edge;
    ev.xclient.data.l[3] = Button1;
    ev.xclient.data.l[4] = 1;

    XSendEvent(dpy, DefaultRootWindow(dpy), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(dpy);

    return TCL_OK;
}

int DoMoveId(Tcl_Interp *interp, long winId) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)winId;

    Window root_ret, child_ret;
    int root_x, root_y, win_x, win_y;
    unsigned int mask;
    XQueryPointer(dpy, DefaultRootWindow(dpy), &root_ret, &child_ret,
                  &root_x, &root_y, &win_x, &win_y, &mask);

    Atom moveresize = XInternAtom(dpy, "_NET_WM_MOVERESIZE", False);

    XEvent ev = {0};
    ev.xclient.type = ClientMessage;
    ev.xclient.message_type = moveresize;
    ev.xclient.display = dpy;
    ev.xclient.window = win;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = root_x;
    ev.xclient.data.l[1] = root_y;
    ev.xclient.data.l[2] = 8;
    ev.xclient.data.l[3] = Button1;
    ev.xclient.data.l[4] = 1;

    XSendEvent(dpy, DefaultRootWindow(dpy), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(dpy);

    return TCL_OK;
}

int DoActivateId(Tcl_Interp *interp, long winId) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)winId;
    Window root = DefaultRootWindow(dpy);

    Atom activeWin = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);

    XEvent ev = {0};
    ev.xclient.type = ClientMessage;
    ev.xclient.message_type = activeWin;
    ev.xclient.display = dpy;
    ev.xclient.window = win;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = 1;
    ev.xclient.data.l[1] = CurrentTime;
    ev.xclient.data.l[2] = 0;

    XSendEvent(dpy, root, False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(dpy);

    return TCL_OK;
}
