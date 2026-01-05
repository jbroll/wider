/* TkX_core.c - Common helper functions */

#include "TkX.h"

/* Global atom cache */
AtomCache Atoms = {0};

void InitAtoms(Display *dpy) {
    if (Atoms.dpy == dpy) return;
    Atoms.dpy = dpy;
    Atoms.NET_CLIENT_LIST    = XInternAtom(dpy, "_NET_CLIENT_LIST", False);
    Atoms.NET_WM_DESKTOP     = XInternAtom(dpy, "_NET_WM_DESKTOP", False);
    Atoms.NET_WM_NAME        = XInternAtom(dpy, "_NET_WM_NAME", False);
    Atoms.NET_WM_PID         = XInternAtom(dpy, "_NET_WM_PID", False);
    Atoms.NET_WM_STATE       = XInternAtom(dpy, "_NET_WM_STATE", False);
    Atoms.NET_WM_STATE_ABOVE = XInternAtom(dpy, "_NET_WM_STATE_ABOVE", False);
    Atoms.NET_ACTIVE_WINDOW  = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);
    Atoms.NET_WM_MOVERESIZE  = XInternAtom(dpy, "_NET_WM_MOVERESIZE", False);
    Atoms.NET_FRAME_EXTENTS  = XInternAtom(dpy, "_NET_FRAME_EXTENTS", False);
    Atoms.MOTIF_WM_HINTS     = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);
    Atoms.WM_WINDOW_ROLE     = XInternAtom(dpy, "WM_WINDOW_ROLE", False);
    Atoms.UTF8_STRING        = XInternAtom(dpy, "UTF8_STRING", False);
}

Display* GetDisplay(Tcl_Interp *interp) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) return NULL;
    Display *dpy = Tk_Display(tkwin);
    InitAtoms(dpy);
    return dpy;
}

void SendClientMessage(Display *dpy, Window win, Atom msgType,
                       long d0, long d1, long d2, long d3, long d4) {
    Window root = DefaultRootWindow(dpy);
    XEvent ev = {0};
    ev.xclient.type = ClientMessage;
    ev.xclient.window = win;
    ev.xclient.message_type = msgType;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = d0;
    ev.xclient.data.l[1] = d1;
    ev.xclient.data.l[2] = d2;
    ev.xclient.data.l[3] = d3;
    ev.xclient.data.l[4] = d4;
    XSendEvent(dpy, root, False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(dpy);
}

Window WalkToFrame(Display *dpy, Window win, int *offX, int *offY) {
    Window root = DefaultRootWindow(dpy);
    Window parent, *children;
    unsigned int nchildren;
    XWindowAttributes attr;

    *offX = 0;
    *offY = 0;

    while (1) {
        if (!XQueryTree(dpy, win, &root, &parent, &children, &nchildren))
            return win;
        if (children) XFree(children);
        if (parent == root)
            return win;

        if (XGetWindowAttributes(dpy, win, &attr)) {
            *offX += attr.x;
            *offY += attr.y;
        }
        win = parent;
    }
}

int GetWinInfo(Tcl_Interp *interp, const char *winPath, WinInfo *info) {
    Tk_Window tkwin = Tk_NameToWindow(interp, winPath, Tk_MainWindow(interp));
    if (!tkwin) {
        Tcl_SetObjResult(interp, Tcl_ObjPrintf("window \"%s\" not found", winPath));
        return TCL_ERROR;
    }

    info->dpy = Tk_Display(tkwin);
    InitAtoms(info->dpy);
    info->tkWin = Tk_WindowId(tkwin);
    if (info->tkWin == None) {
        Tcl_SetResult(interp, "window not yet mapped", TCL_STATIC);
        return TCL_ERROR;
    }

    info->frameWin = WalkToFrame(info->dpy, info->tkWin, &info->offX, &info->offY);

    XWindowAttributes attr;
    if (XGetWindowAttributes(info->dpy, info->frameWin, &attr)) {
        info->frameW = attr.width;
        info->frameH = attr.height;
    } else {
        info->frameW = 0;
        info->frameH = 0;
    }

    return TCL_OK;
}

int dir_to_edge(const char *dir) {
    static const struct { const char *name; int edge; } dirs[] = {
        {"nw",    NET_WM_MOVERESIZE_SIZE_TOPLEFT},
        {"north", NET_WM_MOVERESIZE_SIZE_TOP},
        {"ne",    NET_WM_MOVERESIZE_SIZE_TOPRIGHT},
        {"east",  NET_WM_MOVERESIZE_SIZE_RIGHT},
        {"se",    NET_WM_MOVERESIZE_SIZE_BOTTOMRIGHT},
        {"south", NET_WM_MOVERESIZE_SIZE_BOTTOM},
        {"sw",    NET_WM_MOVERESIZE_SIZE_BOTTOMLEFT},
        {"west",  NET_WM_MOVERESIZE_SIZE_LEFT},
        {NULL, -1}
    };
    for (int i = 0; dirs[i].name; i++) {
        if (!strcmp(dir, dirs[i].name)) return dirs[i].edge;
    }
    return -1;
}

Visual* FindARGBVisual(Display *dpy, int screen, int *depth_out) {
    XVisualInfo vinfo_template;
    vinfo_template.screen = screen;
    vinfo_template.depth = 32;
    vinfo_template.class = TrueColor;

    int num_visuals;
    XVisualInfo *visuals = XGetVisualInfo(dpy,
        VisualScreenMask | VisualDepthMask | VisualClassMask,
        &vinfo_template, &num_visuals);

    if (!visuals || num_visuals == 0) {
        if (visuals) XFree(visuals);
        return NULL;
    }

    Visual *result = NULL;
    for (int i = 0; i < num_visuals; i++) {
        XRenderPictFormat *fmt = XRenderFindVisualFormat(dpy, visuals[i].visual);
        if (fmt && fmt->type == PictTypeDirect && fmt->direct.alphaMask) {
            result = visuals[i].visual;
            *depth_out = visuals[i].depth;
            break;
        }
    }

    XFree(visuals);
    return result;
}
