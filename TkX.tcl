# TkX.tcl - X11 extensions for Tk
#
# Provides:
#   TkX::capture <photo> root|<window_id> x y width height  - Capture window to photo
#   TkX::input_hole <window> x y w h      - Set input shape hole (click-through)
#   TkX::input_reset <window>             - Reset input shape
#   TkX::bounding_hole <window> x y w h   - Set bounding shape hole (visual)
#   TkX::bounding_reset <window>          - Reset bounding shape
#   TkX::shape_watch <window> <callback>  - Call callback on ShapeNotify (empty to cancel)
#   TkX::nodecor <window>                 - Remove window decorations
#   TkX::move <window>                    - Initiate WM-controlled move
#   TkX::resize <window> <direction>      - Initiate WM-controlled resize
#   TkX::frame_offset <window>            - Get {offX offY} from Tk window to WM frame
#   TkX::rgba_available                   - Check if 32-bit ARGB visual is available
#   TkX::rgba_clear <window> x y w h      - Clear region to transparent (XRender)
#   TkX::rgba_overlay <window>            - Create ARGB overlay window, returns window ID
#   TkX::rgba_child <window> x y w h      - Create ARGB child window, returns window ID
#   TkX::window_geometry <id> x y w h     - Move/resize X11 window by ID
#   TkX::window_destroy <id>              - Destroy X11 window by ID
#
# Build: critcl -pkg TkX.tcl

package require Tcl 9.0
package require critcl 3.2

critcl::tcl 9.1
critcl::tk

critcl::clibraries -L/home/john/lib -ltclstub -ltkstub -lX11 -lXext -lXrender

critcl::ccode {
    #include <X11/Xlib.h>
    #include <X11/Xutil.h>
    #include <X11/Xatom.h>
    #include <X11/extensions/shape.h>
    #include <X11/extensions/Xrender.h>
    #include <stdlib.h>
    #include <string.h>

    /* ========== Constants ========== */

    #define NET_WM_MOVERESIZE_SIZE_TOPLEFT      0
    #define NET_WM_MOVERESIZE_SIZE_TOP          1
    #define NET_WM_MOVERESIZE_SIZE_TOPRIGHT     2
    #define NET_WM_MOVERESIZE_SIZE_RIGHT        3
    #define NET_WM_MOVERESIZE_SIZE_BOTTOMRIGHT  4
    #define NET_WM_MOVERESIZE_SIZE_BOTTOM       5
    #define NET_WM_MOVERESIZE_SIZE_BOTTOMLEFT   6
    #define NET_WM_MOVERESIZE_SIZE_LEFT         7
    #define NET_WM_MOVERESIZE_MOVE              8

    /* ========== Common Window Info ========== */

    typedef struct {
        Display *dpy;
        Window tkWin;
        Window frameWin;
        int offX, offY;     /* Offset from Tk window to frame */
        int frameW, frameH; /* Frame window dimensions */
    } WinInfo;

    /* Walk up window tree to find frame and compute offset.
     * Returns frame window and cumulative offset from win to frame. */
    static Window WalkToFrame(Display *dpy, Window win, int *offX, int *offY) {
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
                return win;  /* This is the frame window */

            /* Accumulate offset */
            if (XGetWindowAttributes(dpy, win, &attr)) {
                *offX += attr.x;
                *offY += attr.y;
            }
            win = parent;
        }
    }

    /* Get window info from Tk path. Returns TCL_OK or TCL_ERROR with message set. */
    static int GetWinInfo(Tcl_Interp *interp, const char *winPath, WinInfo *info) {
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

    /* ========== Capture ========== */

    static int DoCapture(Tcl_Interp *interp, const char *photoName,
                         const char *winArg, int x, int y, int w, int h) {
        Tk_PhotoHandle photo = Tk_FindPhoto(interp, photoName);
        if (!photo) {
            Tcl_SetObjResult(interp, Tcl_ObjPrintf("photo \"%s\" not found", photoName));
            return TCL_ERROR;
        }

        Tk_Window tkwin = Tk_MainWindow(interp);
        if (!tkwin) {
            Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
            return TCL_ERROR;
        }
        Display *dpy = Tk_Display(tkwin);

        Window win;
        if (strcmp(winArg, "root") == 0) {
            win = DefaultRootWindow(dpy);
        } else {
            char *endptr;
            long winId = strtol(winArg, &endptr, 0);
            if (*endptr != '\0') {
                Tcl_SetObjResult(interp, Tcl_ObjPrintf("invalid window id \"%s\"", winArg));
                return TCL_ERROR;
            }
            win = (Window)winId;
        }

        XImage *img = XGetImage(dpy, win, x, y, (unsigned)w, (unsigned)h, AllPlanes, ZPixmap);
        if (!img) {
            Tcl_SetResult(interp, "XGetImage failed", TCL_STATIC);
            return TCL_ERROR;
        }

        Tk_PhotoSetSize(interp, photo, w, h);

        unsigned char *data = (unsigned char *)ckalloc(w * h * 4);
        if (!data) {
            XDestroyImage(img);
            Tcl_SetResult(interp, "memory allocation failed", TCL_STATIC);
            return TCL_ERROR;
        }

        unsigned char *p = data;
        for (int j = 0; j < h; j++) {
            for (int i = 0; i < w; i++) {
                unsigned long pixel = XGetPixel(img, i, j);
                *p++ = (pixel >> 16) & 0xff;
                *p++ = (pixel >> 8) & 0xff;
                *p++ = pixel & 0xff;
                *p++ = 255;
            }
        }
        XDestroyImage(img);

        Tk_PhotoImageBlock block;
        block.pixelPtr = data;
        block.width = w;
        block.height = h;
        block.pitch = w * 4;
        block.pixelSize = 4;
        block.offset[0] = 0;
        block.offset[1] = 1;
        block.offset[2] = 2;
        block.offset[3] = 3;

        Tk_PhotoPutBlock(interp, photo, &block, 0, 0, w, h, TK_PHOTO_COMPOSITE_SET);
        ckfree((char *)data);

        return TCL_OK;
    }

    /* ========== Shape ========== */

    /* Build rectangles that cover everything except the hole.
     * Returns number of rectangles (0-4). */
    static int MakeHoleRects(XRectangle *rects, int ww, int wh,
                             int hx, int hy, int hw, int hh) {
        int n = 0;

        /* Top strip */
        if (hy > 0) {
            rects[n].x = 0;
            rects[n].y = 0;
            rects[n].width = ww;
            rects[n].height = hy;
            n++;
        }
        /* Bottom strip */
        if (hy + hh < wh) {
            rects[n].x = 0;
            rects[n].y = hy + hh;
            rects[n].width = ww;
            rects[n].height = wh - (hy + hh);
            n++;
        }
        /* Left strip (middle section only) */
        if (hx > 0) {
            rects[n].x = 0;
            rects[n].y = hy;
            rects[n].width = hx;
            rects[n].height = hh;
            n++;
        }
        /* Right strip (middle section only) */
        if (hx + hw < ww) {
            rects[n].x = hx + hw;
            rects[n].y = hy;
            rects[n].width = ww - (hx + hw);
            rects[n].height = hh;
            n++;
        }
        return n;
    }

    static int DoSetHole(Tcl_Interp *interp, const char *winPath,
                         int kind, int hx, int hy, int hw, int hh) {
        WinInfo wi;
        if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
            return TCL_ERROR;

        /* Transform hole coords from Tk window to frame */
        hx += wi.offX;
        hy += wi.offY;

        XRectangle rects[4];
        int nrects = MakeHoleRects(rects, wi.frameW, wi.frameH, hx, hy, hw, hh);

        XShapeCombineRectangles(wi.dpy, wi.frameWin, kind, 0, 0,
                                rects, nrects, ShapeSet, Unsorted);
        XFlush(wi.dpy);

        return TCL_OK;
    }

    static int DoResetShape(Tcl_Interp *interp, const char *winPath, int kind) {
        WinInfo wi;
        if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
            return TCL_ERROR;

        XShapeCombineMask(wi.dpy, wi.frameWin, kind, 0, 0, None, ShapeSet);
        XFlush(wi.dpy);

        return TCL_OK;
    }

    /* ========== ShapeNotify ========== */

    typedef struct ShapeWatch {
        Window frameWin;
        Tcl_Interp *interp;
        Tcl_Obj *callback;
        struct ShapeWatch *next;
    } ShapeWatch;

    static ShapeWatch *shapeWatchList = NULL;
    static int shapeEventBase = 0;
    static int shapeErrorBase = 0;
    static int shapeHandlerInstalled = 0;

    static int ShapeEventHandler(ClientData clientData, XEvent *eventPtr) {
        (void)clientData;
        if (shapeEventBase == 0) return 0;
        if (eventPtr->type != shapeEventBase + ShapeNotify) return 0;

        XShapeEvent *shapeEvent = (XShapeEvent *)eventPtr;
        Window win = shapeEvent->window;

        for (ShapeWatch *w = shapeWatchList; w; w = w->next) {
            if (w->frameWin == win) {
                Tcl_EvalObjEx(w->interp, w->callback, TCL_EVAL_GLOBAL);
                return 1;
            }
        }
        return 0;
    }

    static int DoShapeWatch(Tcl_Interp *interp, const char *winPath, Tcl_Obj *callback) {
        WinInfo wi;
        if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
            return TCL_ERROR;

        /* Initialize shape extension if needed */
        if (shapeEventBase == 0) {
            if (!XShapeQueryExtension(wi.dpy, &shapeEventBase, &shapeErrorBase)) {
                Tcl_SetResult(interp, "Shape extension not available", TCL_STATIC);
                return TCL_ERROR;
            }
        }

        /* Install handler once */
        if (!shapeHandlerInstalled) {
            Tk_CreateGenericHandler(ShapeEventHandler, NULL);
            shapeHandlerInstalled = 1;
        }

        /* Remove existing watch for this window */
        ShapeWatch **pp = &shapeWatchList;
        while (*pp) {
            ShapeWatch *w = *pp;
            if (w->frameWin == wi.frameWin) {
                *pp = w->next;
                Tcl_DecrRefCount(w->callback);
                ckfree((char *)w);
                break;
            }
            pp = &w->next;
        }

        /* Empty callback = just remove watch */
        Tcl_Size len;
        Tcl_GetStringFromObj(callback, &len);
        if (len == 0) {
            XShapeSelectInput(wi.dpy, wi.frameWin, 0);
            return TCL_OK;
        }

        /* Add new watch */
        ShapeWatch *w = (ShapeWatch *)ckalloc(sizeof(ShapeWatch));
        w->frameWin = wi.frameWin;
        w->interp = interp;
        w->callback = callback;
        Tcl_IncrRefCount(callback);
        w->next = shapeWatchList;
        shapeWatchList = w;

        XShapeSelectInput(wi.dpy, wi.frameWin, ShapeNotifyMask);

        return TCL_OK;
    }

    /* ========== CSD (Client-Side Decorations) ========== */

    typedef struct {
        unsigned long flags;
        unsigned long functions;
        unsigned long decorations;
        long          input_mode;
        unsigned long status;
    } MotifWmHints;

    #define MWM_HINTS_DECORATIONS (1L << 1)

    static int DoNodecor(Tcl_Interp *interp, const char *winPath) {
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

    static int dir_to_edge(const char *dir) {
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

    static int DoMove(Tcl_Interp *interp, const char *winPath) {
        return DoMoveResize(interp, winPath, NET_WM_MOVERESIZE_MOVE);
    }

    static int DoResize(Tcl_Interp *interp, const char *winPath, const char *direction) {
        int edge = dir_to_edge(direction);
        if (edge < 0) {
            Tcl_SetResult(interp, "invalid direction: use nw north ne east se south sw west", TCL_STATIC);
            return TCL_ERROR;
        }
        return DoMoveResize(interp, winPath, edge);
    }

    /* ========== RGBA Transparency ========== */

    /* Find a 32-bit ARGB visual for true transparency */
    static Visual* FindARGBVisual(Display *dpy, int screen, int *depth_out) {
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

        /* Find one with alpha channel (32-bit with proper masks) */
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

    /* Check if RGBA visual is available */
    static int DoRGBACheck(Tcl_Interp *interp) {
        Tk_Window tkwin = Tk_MainWindow(interp);
        if (!tkwin) {
            Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
            return TCL_ERROR;
        }

        Display *dpy = Tk_Display(tkwin);
        int screen = DefaultScreen(dpy);
        int depth;

        Visual *argbVisual = FindARGBVisual(dpy, screen, &depth);
        Tcl_SetObjResult(interp, Tcl_NewBooleanObj(argbVisual != NULL));
        return TCL_OK;
    }

    /* Clear a region to transparent using XRender.
     * Note: This only works on windows with ARGB visual or with compositor. */
    static int DoClearRegion(Tcl_Interp *interp, const char *winPath,
                             int x, int y, int w, int h) {
        WinInfo wi;
        if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
            return TCL_ERROR;

        /* Get XRender picture format for the window */
        XRenderPictFormat *fmt = XRenderFindVisualFormat(wi.dpy,
            DefaultVisual(wi.dpy, DefaultScreen(wi.dpy)));
        if (!fmt) {
            Tcl_SetResult(interp, "XRender format not found", TCL_STATIC);
            return TCL_ERROR;
        }

        /* Create picture for the window */
        XRenderPictureAttributes pa;
        pa.subwindow_mode = IncludeInferiors;
        Picture pic = XRenderCreatePicture(wi.dpy, wi.tkWin, fmt,
                                           CPSubwindowMode, &pa);
        if (!pic) {
            Tcl_SetResult(interp, "failed to create XRender picture", TCL_STATIC);
            return TCL_ERROR;
        }

        /* Clear with fully transparent color */
        XRenderColor clear = {0, 0, 0, 0};  /* RGBA all zero = fully transparent */
        XRenderFillRectangle(wi.dpy, PictOpSrc, pic, &clear, x, y, w, h);

        XRenderFreePicture(wi.dpy, pic);
        XFlush(wi.dpy);

        return TCL_OK;
    }

    /* Create ARGB window as overlay. Returns window ID or 0 on failure.
     * The overlay window will be a child of root, positioned over the Tk window. */
    static int DoCreateARGBOverlay(Tcl_Interp *interp, const char *winPath) {
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

        /* Get Tk window geometry */
        XWindowAttributes tkAttr;
        if (!XGetWindowAttributes(wi.dpy, wi.tkWin, &tkAttr)) {
            Tcl_SetResult(interp, "failed to get window attributes", TCL_STATIC);
            return TCL_ERROR;
        }

        /* Get absolute position */
        Window child;
        int absX, absY;
        XTranslateCoordinates(wi.dpy, wi.tkWin, DefaultRootWindow(wi.dpy),
                              0, 0, &absX, &absY, &child);

        /* Create colormap for ARGB visual */
        Colormap cmap = XCreateColormap(wi.dpy, DefaultRootWindow(wi.dpy),
                                        argbVisual, AllocNone);

        /* Create ARGB window */
        XSetWindowAttributes attr;
        attr.colormap = cmap;
        attr.background_pixel = 0;  /* Transparent */
        attr.border_pixel = 0;
        attr.override_redirect = True;  /* No WM decorations */

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

        /* Return the window ID */
        Tcl_SetObjResult(interp, Tcl_NewWideIntObj((Tcl_WideInt)overlay));
        return TCL_OK;
    }

    /* Create ARGB child window inside a Tk window.
     * The child is fully transparent and can be used for true transparency.
     * Returns window ID. */
    static int DoCreateARGBChild(Tcl_Interp *interp, const char *winPath,
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

        /* Create colormap for ARGB visual */
        Colormap cmap = XCreateColormap(wi.dpy, DefaultRootWindow(wi.dpy),
                                        argbVisual, AllocNone);

        /* Create ARGB child window inside the Tk window */
        XSetWindowAttributes attr;
        attr.colormap = cmap;
        attr.background_pixel = 0;  /* Fully transparent */
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

        /* Map the window immediately */
        XMapWindow(wi.dpy, child);
        XFlush(wi.dpy);

        /* Return the window ID */
        Tcl_SetObjResult(interp, Tcl_NewWideIntObj((Tcl_WideInt)child));
        return TCL_OK;
    }

    /* Move and resize an X11 window */
    static int DoMoveResizeWindow(Tcl_Interp *interp, long winId,
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

    /* Destroy an X11 window */
    static int DoDestroyWindow(Tcl_Interp *interp, long winId) {
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

    /* ========== Window Listing ========== */

    /* List all top-level windows managed by WM.
     * Returns list of dicts: {id x y w h class} */
    static int DoListWindows(Tcl_Interp *interp) {
        Tk_Window tkwin = Tk_MainWindow(interp);
        if (!tkwin) {
            Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
            return TCL_ERROR;
        }
        Display *dpy = Tk_Display(tkwin);
        Window root = DefaultRootWindow(dpy);

        /* Get _NET_CLIENT_LIST for managed windows */
        Atom clientList = XInternAtom(dpy, "_NET_CLIENT_LIST", False);
        Atom netWmDesktop = XInternAtom(dpy, "_NET_WM_DESKTOP", False);
        Atom actualType;
        int actualFormat;
        unsigned long nitems, bytesAfter;
        unsigned char *data = NULL;

        if (XGetWindowProperty(dpy, root, clientList, 0, 1024, False,
                               XA_WINDOW, &actualType, &actualFormat,
                               &nitems, &bytesAfter, &data) != Success || !data) {
            Tcl_SetResult(interp, "failed to get _NET_CLIENT_LIST", TCL_STATIC);
            return TCL_ERROR;
        }

        Window *windows = (Window *)data;
        Tcl_Obj *resultList = Tcl_NewListObj(0, NULL);

        for (unsigned long i = 0; i < nitems; i++) {
            Window win = windows[i];
            XWindowAttributes attr;
            if (!XGetWindowAttributes(dpy, win, &attr)) continue;

            /* Get WM_CLASS */
            XClassHint classHint = {0};
            char *className = "";
            if (XGetClassHint(dpy, win, &classHint)) {
                className = classHint.res_class ? classHint.res_class : "";
            }

            /* Get absolute position */
            Window child;
            int absX, absY;
            XTranslateCoordinates(dpy, win, root, 0, 0, &absX, &absY, &child);

            /* Get _NET_WM_DESKTOP */
            long desktop = 0;
            unsigned char *desktopData = NULL;
            unsigned long desktopItems;
            if (XGetWindowProperty(dpy, win, netWmDesktop, 0, 1, False,
                                   XA_CARDINAL, &actualType, &actualFormat,
                                   &desktopItems, &bytesAfter, &desktopData) == Success
                && desktopData && desktopItems > 0) {
                desktop = *(long *)desktopData;
                XFree(desktopData);
            }

            /* Build dict for this window */
            Tcl_Obj *winDict = Tcl_NewDictObj();
            Tcl_DictObjPut(interp, winDict,
                Tcl_NewStringObj("id", -1),
                Tcl_ObjPrintf("0x%lx", (unsigned long)win));
            Tcl_DictObjPut(interp, winDict,
                Tcl_NewStringObj("x", -1), Tcl_NewIntObj(absX));
            Tcl_DictObjPut(interp, winDict,
                Tcl_NewStringObj("y", -1), Tcl_NewIntObj(absY));
            Tcl_DictObjPut(interp, winDict,
                Tcl_NewStringObj("w", -1), Tcl_NewIntObj(attr.width));
            Tcl_DictObjPut(interp, winDict,
                Tcl_NewStringObj("h", -1), Tcl_NewIntObj(attr.height));
            Tcl_DictObjPut(interp, winDict,
                Tcl_NewStringObj("class", -1), Tcl_NewStringObj(className, -1));
            Tcl_DictObjPut(interp, winDict,
                Tcl_NewStringObj("desktop", -1), Tcl_NewLongObj(desktop));

            /* Get window title (_NET_WM_NAME or WM_NAME) */
            char *title = NULL;
            Atom netWmName = XInternAtom(dpy, "_NET_WM_NAME", False);
            Atom utf8String = XInternAtom(dpy, "UTF8_STRING", False);
            unsigned char *titleData = NULL;
            unsigned long titleItems;
            if (XGetWindowProperty(dpy, win, netWmName, 0, 256, False,
                                   utf8String, &actualType, &actualFormat,
                                   &titleItems, &bytesAfter, &titleData) == Success
                && titleData && titleItems > 0) {
                title = (char *)titleData;
            } else {
                /* Fallback to WM_NAME */
                XFetchName(dpy, win, &title);
            }
            Tcl_DictObjPut(interp, winDict,
                Tcl_NewStringObj("title", -1),
                Tcl_NewStringObj(title ? title : "", -1));
            if (titleData) XFree(titleData);
            else if (title) XFree(title);

            Tcl_ListObjAppendElement(interp, resultList, winDict);

            if (classHint.res_name) XFree(classHint.res_name);
            if (classHint.res_class) XFree(classHint.res_class);
        }

        XFree(data);
        Tcl_SetObjResult(interp, resultList);
        return TCL_OK;
    }

    /* Get multiple window properties in one call.
     * Returns dict with role, pid, command keys */
    static int DoGetProps(Tcl_Interp *interp, long winId) {
        Tk_Window tkwin = Tk_MainWindow(interp);
        if (!tkwin) {
            Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
            return TCL_ERROR;
        }
        Display *dpy = Tk_Display(tkwin);
        Window win = (Window)winId;

        Tcl_Obj *result = Tcl_NewDictObj();

        /* Get WM_WINDOW_ROLE */
        Atom roleAtom = XInternAtom(dpy, "WM_WINDOW_ROLE", False);
        Atom actualType;
        int actualFormat;
        unsigned long nitems, bytesAfter;
        unsigned char *data = NULL;

        if (XGetWindowProperty(dpy, win, roleAtom, 0, 128, False,
                               XA_STRING, &actualType, &actualFormat,
                               &nitems, &bytesAfter, &data) == Success && data) {
            Tcl_DictObjPut(interp, result,
                Tcl_NewStringObj("role", -1),
                Tcl_NewStringObj((char *)data, nitems));
            XFree(data);
        } else {
            Tcl_DictObjPut(interp, result,
                Tcl_NewStringObj("role", -1), Tcl_NewStringObj("", -1));
        }

        /* Get _NET_WM_PID */
        Atom pidAtom = XInternAtom(dpy, "_NET_WM_PID", False);
        data = NULL;
        if (XGetWindowProperty(dpy, win, pidAtom, 0, 1, False,
                               XA_CARDINAL, &actualType, &actualFormat,
                               &nitems, &bytesAfter, &data) == Success && data && nitems > 0) {
            unsigned long pid = *(unsigned long *)data;
            Tcl_DictObjPut(interp, result,
                Tcl_NewStringObj("pid", -1), Tcl_NewLongObj(pid));
            XFree(data);
        } else {
            Tcl_DictObjPut(interp, result,
                Tcl_NewStringObj("pid", -1), Tcl_NewIntObj(0));
        }

        /* Get WM_COMMAND */
        int argc = 0;
        char **argv = NULL;
        if (XGetCommand(dpy, win, &argv, &argc) && argc > 0) {
            Tcl_Obj *cmdList = Tcl_NewListObj(0, NULL);
            for (int i = 0; i < argc; i++) {
                Tcl_ListObjAppendElement(interp, cmdList,
                    Tcl_NewStringObj(argv[i], -1));
            }
            Tcl_DictObjPut(interp, result,
                Tcl_NewStringObj("command", -1), cmdList);
            XFreeStringList(argv);
        } else {
            Tcl_DictObjPut(interp, result,
                Tcl_NewStringObj("command", -1), Tcl_NewStringObj("", -1));
        }

        Tcl_SetObjResult(interp, result);
        return TCL_OK;
    }

    /* Move and optionally resize an X11 window.
     * Coords are absolute screen coords; we handle the frame offset internally. */
    static int DoMoveWindow(Tcl_Interp *interp, long winId, int x, int y, int w, int h) {
        Tk_Window tkwin = Tk_MainWindow(interp);
        if (!tkwin) {
            Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
            return TCL_ERROR;
        }
        Display *dpy = Tk_Display(tkwin);
        Window win = (Window)winId;
        Window root = DefaultRootWindow(dpy);

        /* Walk up to find frame and compute offset */
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

        /* Move the frame window (current is now the frame) */
        int frameX = x - offX;
        int frameY = y - offY;

        if (w > 0 && h > 0) {
            XMoveResizeWindow(dpy, current, frameX, frameY, w, h);
        } else {
            XMoveWindow(dpy, current, frameX, frameY);
        }
        XFlush(dpy);

        return TCL_OK;
    }

    /* Get frame offset for any X11 window (by ID).
     * Returns {offX offY} - the offset from window coords to frame coords.
     * This is what wmctrl needs subtracted from absolute coords. */
    static int DoWindowOffset(Tcl_Interp *interp, long winId) {
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

        /* Walk up to frame, accumulating offset */
        while (1) {
            if (!XQueryTree(dpy, win, &root, &parent, &children, &nchildren)) {
                break;
            }
            if (children) XFree(children);
            if (parent == root) break;  /* win is the frame */

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

    /* Get the currently focused/active window */
    static int DoGetActiveWindow(Tcl_Interp *interp) {
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

    /* Set window to desktop */
    static int DoSetDesktop(Tcl_Interp *interp, long winId, int desktop) {
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
        ev.xclient.data.l[1] = 2;  /* source indication: pager */

        XSendEvent(dpy, root, False,
                   SubstructureNotifyMask | SubstructureRedirectMask, &ev);
        XFlush(dpy);
        return TCL_OK;
    }

    /* Change window state (add/remove/toggle) */
    static int DoWindowState(Tcl_Interp *interp, long winId, const char *action,
                             const char *prop1, const char *prop2) {
        Tk_Window tkwin = Tk_MainWindow(interp);
        if (!tkwin) {
            Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
            return TCL_ERROR;
        }
        Display *dpy = Tk_Display(tkwin);
        Window root = DefaultRootWindow(dpy);
        Window win = (Window)winId;

        /* Action: 0=remove, 1=add, 2=toggle */
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
        ev.xclient.data.l[3] = 2;  /* source: pager */

        XSendEvent(dpy, root, False,
                   SubstructureNotifyMask | SubstructureRedirectMask, &ev);
        XFlush(dpy);
        return TCL_OK;
    }

    /* Set a string property on a window */
    static int DoSetProperty(Tcl_Interp *interp, long winId,
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

    /* Reparent window to new parent at given position */
    static int DoReparentWindow(Tcl_Interp *interp, long childId,
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

    /* Map (show) an X11 window */
    static int DoMapWindow(Tcl_Interp *interp, long winId) {
        Tk_Window tkwin = Tk_MainWindow(interp);
        if (!tkwin) {
            Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
            return TCL_ERROR;
        }
        Display *dpy = Tk_Display(tkwin);
        Window win = (Window)winId;

        /* Map the window */
        XMapWindow(dpy, win);

        /* Raise it to top */
        XRaiseWindow(dpy, win);

        /* Set _NET_WM_STATE_ABOVE to keep on top */
        Atom wmState = XInternAtom(dpy, "_NET_WM_STATE", False);
        Atom wmStateAbove = XInternAtom(dpy, "_NET_WM_STATE_ABOVE", False);
        XChangeProperty(dpy, win, wmState, XA_ATOM, 32, PropModeReplace,
                        (unsigned char *)&wmStateAbove, 1);

        XFlush(dpy);
        XSync(dpy, False);
        return TCL_OK;
    }

    /* Create standalone ARGB window (not child of anything).
     * Uses the simpler XMatchVisualInfo approach that works with compositors. */
    static int DoCreateARGBWindow(Tcl_Interp *interp,
                                   int x, int y, int w, int h) {
        Tk_Window tkwin = Tk_MainWindow(interp);
        if (!tkwin) {
            Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
            return TCL_ERROR;
        }

        Display *dpy = Tk_Display(tkwin);
        int screen = DefaultScreen(dpy);

        /* Use XMatchVisualInfo to find 32-bit TrueColor visual */
        XVisualInfo vinfo;
        if (!XMatchVisualInfo(dpy, screen, 32, TrueColor, &vinfo)) {
            Tcl_SetResult(interp, "no 32-bit TrueColor visual available", TCL_STATIC);
            return TCL_ERROR;
        }

        /* Create colormap for this visual */
        Colormap cmap = XCreateColormap(dpy, DefaultRootWindow(dpy),
                                        vinfo.visual, AllocNone);

        /* Set window attributes - minimal set like working example */
        XSetWindowAttributes attr;
        attr.colormap = cmap;
        attr.background_pixel = 0;
        attr.border_pixel = 0;

        /* Create window using the visual's depth */
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

        /* Set MOTIF_WM_HINTS to remove decorations */
        Atom prop = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);
        MotifWmHints hints = {0};
        hints.flags = MWM_HINTS_DECORATIONS;
        hints.decorations = 0;
        XChangeProperty(dpy, win, prop, prop, 32, PropModeReplace,
                        (unsigned char *)&hints, 5);

        Tcl_SetObjResult(interp, Tcl_NewLongObj((long)win));
        return TCL_OK;
    }

    /* Draw a filled rectangle on an ARGB window */
    static int DoARGBFillRect(Tcl_Interp *interp, long winId,
                               int x, int y, int w, int h,
                               int r, int g, int b, int a) {
        Tk_Window tkwin = Tk_MainWindow(interp);
        if (!tkwin) {
            Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
            return TCL_ERROR;
        }

        Display *dpy = Tk_Display(tkwin);
        Window win = (Window)winId;
        int screen = DefaultScreen(dpy);

        /* Find the picture format for the window */
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

        /* Create picture for the window */
        Picture pic = XRenderCreatePicture(dpy, win, fmt, 0, NULL);
        if (!pic) {
            Tcl_SetResult(interp, "failed to create picture", TCL_STATIC);
            return TCL_ERROR;
        }

        /* Fill with color (values are 0-255, XRender uses 0-65535) */
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
}

# Capture
critcl::cproc TkX::capture {
    Tcl_Interp* interp
    char* photo
    char* window
    int x
    int y
    int width
    int height
} ok {
    return DoCapture(interp, photo, window, x, y, width, height);
}

# Shape - input
critcl::cproc TkX::input_hole {
    Tcl_Interp* interp
    char* window
    int x
    int y
    int width
    int height
} ok {
    return DoSetHole(interp, window, ShapeInput, x, y, width, height);
}

critcl::cproc TkX::input_reset {
    Tcl_Interp* interp
    char* window
} ok {
    return DoResetShape(interp, window, ShapeInput);
}

# Grab X11 keyboard focus for overrideredirect windows
critcl::cproc TkX::grab_focus {
    Tcl_Interp* interp
    char* window
} ok {
    WinInfo wi;
    if (GetWinInfo(interp, window, &wi) != TCL_OK) return TCL_ERROR;
    XSetInputFocus(wi.dpy, wi.tkWin, RevertToParent, CurrentTime);
    XFlush(wi.dpy);
    return TCL_OK;
}

# Shape - bounding
critcl::cproc TkX::bounding_hole {
    Tcl_Interp* interp
    char* window
    int x
    int y
    int width
    int height
} ok {
    return DoSetHole(interp, window, ShapeBounding, x, y, width, height);
}

critcl::cproc TkX::bounding_reset {
    Tcl_Interp* interp
    char* window
} ok {
    return DoResetShape(interp, window, ShapeBounding);
}

# Shape notification
critcl::cproc TkX::shape_watch {
    Tcl_Interp* interp
    char* window
    Tcl_Obj* callback
} ok {
    return DoShapeWatch(interp, window, callback);
}

# CSD
critcl::cproc TkX::nodecor {
    Tcl_Interp* interp
    char* window
} ok {
    return DoNodecor(interp, window);
}

critcl::cproc TkX::move {
    Tcl_Interp* interp
    char* window
} ok {
    return DoMove(interp, window);
}

critcl::cproc TkX::resize {
    Tcl_Interp* interp
    char* window
    char* direction
} ok {
    return DoResize(interp, window, direction);
}

# Get frame offset - returns {offX offY} from Tk window to WM frame
critcl::cproc TkX::frame_offset {
    Tcl_Interp* interp
    char* window
} ok {
    WinInfo wi;
    if (GetWinInfo(interp, window, &wi) != TCL_OK)
        return TCL_ERROR;

    Tcl_Obj *result = Tcl_NewListObj(0, NULL);
    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(wi.offX));
    Tcl_ListObjAppendElement(interp, result, Tcl_NewIntObj(wi.offY));
    Tcl_SetObjResult(interp, result);
    return TCL_OK;
}

# RGBA - check if ARGB visual is available
critcl::cproc TkX::rgba_available {
    Tcl_Interp* interp
} ok {
    return DoRGBACheck(interp);
}

# RGBA - clear a region to transparent (requires compositor)
critcl::cproc TkX::rgba_clear {
    Tcl_Interp* interp
    char* window
    int x
    int y
    int width
    int height
} ok {
    return DoClearRegion(interp, window, x, y, width, height);
}

# RGBA - create ARGB overlay window, returns window ID
critcl::cproc TkX::rgba_overlay {
    Tcl_Interp* interp
    char* window
} ok {
    return DoCreateARGBOverlay(interp, window);
}

# RGBA - create ARGB child window inside a Tk window, returns window ID
critcl::cproc TkX::rgba_child {
    Tcl_Interp* interp
    char* window
    int x
    int y
    int width
    int height
} ok {
    return DoCreateARGBChild(interp, window, x, y, width, height);
}

# Window management - move/resize an X11 window by ID
critcl::cproc TkX::window_geometry {
    Tcl_Interp* interp
    long window_id
    int x
    int y
    int width
    int height
} ok {
    return DoMoveResizeWindow(interp, window_id, x, y, width, height);
}

# Window management - destroy an X11 window by ID
critcl::cproc TkX::window_destroy {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoDestroyWindow(interp, window_id);
}

# Window management - reparent window to new parent
critcl::cproc TkX::reparent {
    Tcl_Interp* interp
    long child_id
    long parent_id
    int x
    int y
} ok {
    return DoReparentWindow(interp, child_id, parent_id, x, y);
}

# Window management - initiate WM resize on window by ID
critcl::cproc TkX::resize_id {
    Tcl_Interp* interp
    long window_id
    char* direction
} ok {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)window_id;

    int edge = dir_to_edge(direction);
    if (edge < 0) {
        Tcl_SetResult(interp, "invalid direction: use nw north ne east se south sw west", TCL_STATIC);
        return TCL_ERROR;
    }

    /* Get current pointer position */
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
    ev.xclient.data.l[4] = 1;  /* source indication: normal application */

    XSendEvent(dpy, DefaultRootWindow(dpy), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(dpy);

    return TCL_OK;
}

# Window management - initiate WM move on window by ID
critcl::cproc TkX::move_id {
    Tcl_Interp* interp
    long window_id
} ok {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)window_id;

    /* Get current pointer position */
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
    ev.xclient.data.l[2] = 8;  /* _NET_WM_MOVERESIZE_MOVE */
    ev.xclient.data.l[3] = Button1;
    ev.xclient.data.l[4] = 1;  /* source indication: normal application */

    XSendEvent(dpy, DefaultRootWindow(dpy), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(dpy);

    return TCL_OK;
}

# Window management - set background pixel to transparent (for 32-bit windows)
critcl::cproc TkX::set_transparent_bg {
    Tcl_Interp* interp
    char* window
} ok {
    WinInfo wi;
    if (GetWinInfo(interp, window, &wi) != TCL_OK)
        return TCL_ERROR;

    /* Set background_pixel to 0 (fully transparent on ARGB) */
    XSetWindowBackground(wi.dpy, wi.tkWin, 0);
    XClearWindow(wi.dpy, wi.tkWin);
    XFlush(wi.dpy);

    return TCL_OK;
}

# Window management - activate window (give it focus)
critcl::cproc TkX::activate_id {
    Tcl_Interp* interp
    long window_id
} ok {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)window_id;
    Window root = DefaultRootWindow(dpy);

    /* Send _NET_ACTIVE_WINDOW to request activation */
    Atom activeWin = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);

    XEvent ev = {0};
    ev.xclient.type = ClientMessage;
    ev.xclient.message_type = activeWin;
    ev.xclient.display = dpy;
    ev.xclient.window = win;
    ev.xclient.format = 32;
    ev.xclient.data.l[0] = 1;  /* source: application */
    ev.xclient.data.l[1] = CurrentTime;
    ev.xclient.data.l[2] = 0;  /* currently active window (none) */

    XSendEvent(dpy, root, False,
               SubstructureRedirectMask | SubstructureNotifyMask, &ev);
    XFlush(dpy);

    return TCL_OK;
}

# Window management - map (show) an X11 window by ID
critcl::cproc TkX::window_map {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoMapWindow(interp, window_id);
}

# RGBA - create standalone ARGB window, returns window ID
critcl::cproc TkX::rgba_window {
    Tcl_Interp* interp
    int x
    int y
    int width
    int height
} ok {
    return DoCreateARGBWindow(interp, x, y, width, height);
}

# RGBA - fill rectangle with RGBA color (0-255 for each component)
critcl::cproc TkX::rgba_fill {
    Tcl_Interp* interp
    long window_id
    int x
    int y
    int width
    int height
    int r
    int g
    int b
    int a
} ok {
    return DoARGBFillRect(interp, window_id, x, y, width, height, r, g, b, a);
}

# Window listing - list all top-level windows (fast, no exec)
critcl::cproc TkX::list_windows {
    Tcl_Interp* interp
} ok {
    return DoListWindows(interp);
}

# Window properties - get role, pid, command in one call (fast, no exec)
critcl::cproc TkX::get_props {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoGetProps(interp, window_id);
}

# Window offset - get {offX offY} for wmctrl coordinate conversion (fast, no exec)
critcl::cproc TkX::window_offset {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoWindowOffset(interp, window_id);
}

# Move/resize window - absolute screen coords, handles frame offset internally
# w,h of -1 means move only (no resize)
critcl::cproc TkX::move_window {
    Tcl_Interp* interp
    long window_id
    int x
    int y
    int w
    int h
} ok {
    return DoMoveWindow(interp, window_id, x, y, w, h);
}

# Get the currently active/focused window ID
critcl::cproc TkX::active_window {
    Tcl_Interp* interp
} ok {
    return DoGetActiveWindow(interp);
}

# Set window to a desktop
critcl::cproc TkX::set_desktop {
    Tcl_Interp* interp
    long window_id
    int desktop
} ok {
    return DoSetDesktop(interp, window_id, desktop);
}

# Change window state (add/remove/toggle properties like maximized, above, etc)
critcl::cproc TkX::window_state {
    Tcl_Interp* interp
    long window_id
    char* action
    char* prop1
    char* prop2
} ok {
    return DoWindowState(interp, window_id, action, prop1, prop2);
}

# Set a string property on a window
critcl::cproc TkX::set_property {
    Tcl_Interp* interp
    long window_id
    char* property
    char* value
} ok {
    return DoSetProperty(interp, window_id, property, value);
}

package provide TkX 1.0
