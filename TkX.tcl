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
#
# Build: critcl -pkg TkX.tcl

package require Tcl 8.6
package require critcl 3.2

critcl::tcl 8.6
critcl::tk

critcl::clibraries -lX11 -lXext

critcl::ccode {
    #include <X11/Xlib.h>
    #include <X11/Xutil.h>
    #include <X11/Xatom.h>
    #include <X11/extensions/shape.h>
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
        int len;
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

package provide TkX 1.0
