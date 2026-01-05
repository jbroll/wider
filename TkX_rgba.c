/* TkX_rgba.c - ARGB windows, transparency */

#include "TkX.h"

int DoRGBACheck(Tcl_Interp *interp) {
    REQUIRE_DISPLAY(interp, dpy);
    int screen = DefaultScreen(dpy);
    int depth;

    Visual *argbVisual = FindARGBVisual(dpy, screen, &depth);
    Tcl_SetObjResult(interp, Tcl_NewBooleanObj(argbVisual != NULL));
    return TCL_OK;
}

int DoClearRegion(Tcl_Interp *interp, const char *winPath,
                  int x, int y, int w, int h) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    XRenderPictFormat *fmt = XRenderFindVisualFormat(wi.dpy,
        DefaultVisual(wi.dpy, DefaultScreen(wi.dpy)));
    if (!fmt) {
        Tcl_SetResult(interp, "XRender format not found", TCL_STATIC);
        return TCL_ERROR;
    }

    XRenderPictureAttributes pa;
    pa.subwindow_mode = IncludeInferiors;
    Picture pic = XRenderCreatePicture(wi.dpy, wi.tkWin, fmt,
                                       CPSubwindowMode, &pa);
    if (!pic) {
        Tcl_SetResult(interp, "failed to create XRender picture", TCL_STATIC);
        return TCL_ERROR;
    }

    XRenderColor clear = {0, 0, 0, 0};
    XRenderFillRectangle(wi.dpy, PictOpSrc, pic, &clear, x, y, w, h);

    XRenderFreePicture(wi.dpy, pic);
    XFlush(wi.dpy);

    return TCL_OK;
}

int DoCreateARGBOverlay(Tcl_Interp *interp, const char *winPath) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    int screen = DefaultScreen(wi.dpy);
    int depth;
    Visual *argbVisual = FindARGBVisual(wi.dpy, screen, &depth);

    if (!argbVisual) {
        Tcl_SetResult(interp, "no ARGB visual available", TCL_STATIC);
        return TCL_ERROR;
    }

    XWindowAttributes tkAttr;
    if (!XGetWindowAttributes(wi.dpy, wi.tkWin, &tkAttr)) {
        Tcl_SetResult(interp, "failed to get window attributes", TCL_STATIC);
        return TCL_ERROR;
    }

    Window child;
    int absX, absY;
    XTranslateCoordinates(wi.dpy, wi.tkWin, DefaultRootWindow(wi.dpy),
                          0, 0, &absX, &absY, &child);

    Colormap cmap = XCreateColormap(wi.dpy, DefaultRootWindow(wi.dpy),
                                    argbVisual, AllocNone);

    XSetWindowAttributes attr;
    attr.colormap = cmap;
    attr.background_pixel = 0;
    attr.border_pixel = 0;
    attr.override_redirect = True;

    Window overlay = XCreateWindow(wi.dpy, DefaultRootWindow(wi.dpy),
        absX, absY, tkAttr.width, tkAttr.height, 0,
        depth, InputOutput, argbVisual,
        CWColormap | CWBackPixel | CWBorderPixel | CWOverrideRedirect,
        &attr);

    if (!overlay) {
        XFreeColormap(wi.dpy, cmap);
        Tcl_SetResult(interp, "failed to create ARGB window", TCL_STATIC);
        return TCL_ERROR;
    }

    Tcl_SetObjResult(interp, Tcl_NewWideIntObj((Tcl_WideInt)overlay));
    return TCL_OK;
}

int DoCreateARGBChild(Tcl_Interp *interp, const char *winPath,
                      int x, int y, int w, int h) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    int screen = DefaultScreen(wi.dpy);
    int depth;
    Visual *argbVisual = FindARGBVisual(wi.dpy, screen, &depth);

    if (!argbVisual) {
        Tcl_SetResult(interp, "no ARGB visual available", TCL_STATIC);
        return TCL_ERROR;
    }

    Colormap cmap = XCreateColormap(wi.dpy, DefaultRootWindow(wi.dpy),
                                    argbVisual, AllocNone);

    XSetWindowAttributes attr;
    attr.colormap = cmap;
    attr.background_pixel = 0;
    attr.border_pixel = 0;

    Window child = XCreateWindow(wi.dpy, wi.tkWin,
        x, y, w, h, 0,
        depth, InputOutput, argbVisual,
        CWColormap | CWBackPixel | CWBorderPixel,
        &attr);

    if (!child) {
        XFreeColormap(wi.dpy, cmap);
        Tcl_SetResult(interp, "failed to create ARGB child window", TCL_STATIC);
        return TCL_ERROR;
    }

    XMapWindow(wi.dpy, child);
    XFlush(wi.dpy);

    Tcl_SetObjResult(interp, Tcl_NewWideIntObj((Tcl_WideInt)child));
    return TCL_OK;
}

int DoCreateARGBWindow(Tcl_Interp *interp, int x, int y, int w, int h) {
    REQUIRE_DISPLAY(interp, dpy);
    int screen = DefaultScreen(dpy);

    XVisualInfo vinfo;
    if (!XMatchVisualInfo(dpy, screen, 32, TrueColor, &vinfo)) {
        Tcl_SetResult(interp, "no 32-bit TrueColor visual available", TCL_STATIC);
        return TCL_ERROR;
    }

    Colormap cmap = XCreateColormap(dpy, DefaultRootWindow(dpy),
                                    vinfo.visual, AllocNone);

    XSetWindowAttributes attr;
    attr.colormap = cmap;
    attr.background_pixel = 0;
    attr.border_pixel = 0;

    Screen *scr = DefaultScreenOfDisplay(dpy);
    Window win = XCreateWindow(dpy, RootWindowOfScreen(scr),
        x, y, w, h, 0,
        vinfo.depth, InputOutput, vinfo.visual,
        CWColormap | CWBorderPixel | CWBackPixel,
        &attr);

    if (!win) {
        XFreeColormap(dpy, cmap);
        Tcl_SetResult(interp, "failed to create ARGB window", TCL_STATIC);
        return TCL_ERROR;
    }

    MotifWmHints hints = {0};
    hints.flags = MWM_HINTS_DECORATIONS;
    hints.decorations = 0;
    XChangeProperty(dpy, win, Atoms.MOTIF_WM_HINTS, Atoms.MOTIF_WM_HINTS,
                    32, PropModeReplace, (unsigned char *)&hints, 5);

    Tcl_SetObjResult(interp, Tcl_NewLongObj((long)win));
    return TCL_OK;
}

int DoARGBFillRect(Tcl_Interp *interp, long winId,
                   int x, int y, int w, int h,
                   int r, int g, int b, int a) {
    REQUIRE_DISPLAY(interp, dpy);
    Window win = (Window)winId;

    XWindowAttributes attr;
    if (!XGetWindowAttributes(dpy, win, &attr)) {
        Tcl_SetResult(interp, "failed to get window attributes", TCL_STATIC);
        return TCL_ERROR;
    }

    XRenderPictFormat *fmt = XRenderFindVisualFormat(dpy, attr.visual);
    if (!fmt) {
        Tcl_SetResult(interp, "no XRender format for window", TCL_STATIC);
        return TCL_ERROR;
    }

    Picture pic = XRenderCreatePicture(dpy, win, fmt, 0, NULL);
    if (!pic) {
        Tcl_SetResult(interp, "failed to create picture", TCL_STATIC);
        return TCL_ERROR;
    }

    XRenderColor color;
    color.red   = r * 257;
    color.green = g * 257;
    color.blue  = b * 257;
    color.alpha = a * 257;

    XRenderFillRectangle(dpy, PictOpSrc, pic, &color, x, y, w, h);

    XRenderFreePicture(dpy, pic);
    XFlush(dpy);

    return TCL_OK;
}

int DoMapWindow(Tcl_Interp *interp, long winId) {
    REQUIRE_DISPLAY(interp, dpy);
    Window win = (Window)winId;

    XMapWindow(dpy, win);
    XRaiseWindow(dpy, win);

    XChangeProperty(dpy, win, Atoms.NET_WM_STATE, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *)&Atoms.NET_WM_STATE_ABOVE, 1);

    XFlush(dpy);
    XSync(dpy, False);
    return TCL_OK;
}
