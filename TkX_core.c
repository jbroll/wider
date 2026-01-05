/* TkX_core.c - Common helper functions */

#include "TkX.h"

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
