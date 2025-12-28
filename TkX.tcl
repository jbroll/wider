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
            Tcl_SetResult(interp, "No Tk main window", TCL_STATIC);
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
            Tcl_SetResult(interp, "Memory allocation failed", TCL_STATIC);
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

    /* Find the WM frame window (parent of Tk window up to root) */
    static Window GetFrameWindow(Display *dpy, Window win) {
        Window root = DefaultRootWindow(dpy);
        Window parent, *children;
        unsigned int nchildren;

        while (1) {
            if (!XQueryTree(dpy, win, &root, &parent, &children, &nchildren))
                return win;
            if (children) XFree(children);
            if (parent == root)
                return win;  /* This is the frame window */
            win = parent;
        }
    }

    /* Compute offset from a window to its frame window.
     * Walks up the tree summing each window's position relative to its parent. */
    static void GetFrameOffset(Display *dpy, Window win, int *off_x, int *off_y) {
        Window root = DefaultRootWindow(dpy);
        Window parent, *children;
        unsigned int nchildren;
        XWindowAttributes attr;

        *off_x = 0;
        *off_y = 0;

        while (1) {
            if (!XQueryTree(dpy, win, &root, &parent, &children, &nchildren))
                return;
            if (children) XFree(children);
            if (parent == root)
                return;  /* Reached the frame window */

            /* Get this window's position relative to parent */
            if (XGetWindowAttributes(dpy, win, &attr)) {
                *off_x += attr.x;
                *off_y += attr.y;
            }
            win = parent;
        }
    }

    static int SetHole(Tcl_Interp *interp, const char *winPath,
                       int kind, int hx, int hy, int hw, int hh) {
        Tk_Window tkwin = Tk_NameToWindow(interp, winPath, Tk_MainWindow(interp));
        if (!tkwin) {
            Tcl_SetObjResult(interp, Tcl_ObjPrintf("window \"%s\" not found", winPath));
            return TCL_ERROR;
        }

        Display *dpy = Tk_Display(tkwin);
        Window tkWin = Tk_WindowId(tkwin);
        if (tkWin == None) {
            Tcl_SetResult(interp, "Window not yet mapped", TCL_STATIC);
            return TCL_ERROR;
        }

        /* Get the WM frame window */
        Window win = GetFrameWindow(dpy, tkWin);

        /* Get frame window size */
        XWindowAttributes attr;
        if (!XGetWindowAttributes(dpy, win, &attr)) {
            Tcl_SetResult(interp, "Cannot get window attributes", TCL_STATIC);
            return TCL_ERROR;
        }

        int ww = attr.width;
        int wh = attr.height;

        /* Compute offset from Tk window to frame */
        int off_x, off_y;
        GetFrameOffset(dpy, tkWin, &off_x, &off_y);

        /* Adjust hole position from Tk coords to frame coords */
        hx += off_x;
        hy += off_y;

        XRectangle rects[4];
        int nrects = 0;

        if (hy > 0) {
            rects[nrects].x = 0;
            rects[nrects].y = 0;
            rects[nrects].width = ww;
            rects[nrects].height = hy;
            nrects++;
        }
        if (hy + hh < wh) {
            rects[nrects].x = 0;
            rects[nrects].y = hy + hh;
            rects[nrects].width = ww;
            rects[nrects].height = wh - (hy + hh);
            nrects++;
        }
        if (hx > 0) {
            rects[nrects].x = 0;
            rects[nrects].y = hy;
            rects[nrects].width = hx;
            rects[nrects].height = hh;
            nrects++;
        }
        if (hx + hw < ww) {
            rects[nrects].x = hx + hw;
            rects[nrects].y = hy;
            rects[nrects].width = ww - (hx + hw);
            rects[nrects].height = hh;
            nrects++;
        }

        XShapeCombineRectangles(dpy, win, kind, 0, 0,
                                rects, nrects, ShapeSet, Unsorted);
        XFlush(dpy);

        return TCL_OK;
    }

    static int ResetShape(Tcl_Interp *interp, const char *winPath, int kind) {
        Tk_Window tkwin = Tk_NameToWindow(interp, winPath, Tk_MainWindow(interp));
        if (!tkwin) {
            Tcl_SetObjResult(interp, Tcl_ObjPrintf("window \"%s\" not found", winPath));
            return TCL_ERROR;
        }

        Display *dpy = Tk_Display(tkwin);
        Window tkWin = Tk_WindowId(tkwin);
        if (tkWin == None) {
            Tcl_SetResult(interp, "Window not yet mapped", TCL_STATIC);
            return TCL_ERROR;
        }

        /* Reset shape on the WM frame window */
        Window win = GetFrameWindow(dpy, tkWin);
        XShapeCombineMask(dpy, win, kind, 0, 0, None, ShapeSet);
        XFlush(dpy);

        return TCL_OK;
    }

    /* ========== ShapeNotify ========== */

    /* State for shape notification callbacks */
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

    /* Generic event handler to catch ShapeNotify */
    static int ShapeEventHandler(ClientData clientData, XEvent *eventPtr) {
        if (shapeEventBase == 0) return 0;
        if (eventPtr->type != shapeEventBase + ShapeNotify) return 0;

        XShapeEvent *shapeEvent = (XShapeEvent *)eventPtr;
        Window win = shapeEvent->window;

        /* Find matching watch entry */
        ShapeWatch *watch = shapeWatchList;
        while (watch) {
            if (watch->frameWin == win) {
                /* Evaluate callback */
                Tcl_EvalObjEx(watch->interp, watch->callback, TCL_EVAL_GLOBAL);
                return 1;
            }
            watch = watch->next;
        }
        return 0;
    }

    static int DoShapeWatch(Tcl_Interp *interp, const char *winPath, Tcl_Obj *callback) {
        Tk_Window tkwin = Tk_NameToWindow(interp, winPath, Tk_MainWindow(interp));
        if (!tkwin) {
            Tcl_SetObjResult(interp, Tcl_ObjPrintf("window \"%s\" not found", winPath));
            return TCL_ERROR;
        }

        Display *dpy = Tk_Display(tkwin);
        Window tkWin = Tk_WindowId(tkwin);
        if (tkWin == None) {
            Tcl_SetResult(interp, "Window not yet mapped", TCL_STATIC);
            return TCL_ERROR;
        }

        /* Initialize shape extension if needed */
        if (shapeEventBase == 0) {
            if (!XShapeQueryExtension(dpy, &shapeEventBase, &shapeErrorBase)) {
                Tcl_SetResult(interp, "Shape extension not available", TCL_STATIC);
                return TCL_ERROR;
            }
        }

        /* Install generic handler if not already done */
        if (!shapeHandlerInstalled) {
            Tk_CreateGenericHandler(ShapeEventHandler, NULL);
            shapeHandlerInstalled = 1;
        }

        /* Get frame window */
        Window frameWin = GetFrameWindow(dpy, tkWin);

        /* Remove existing watch for this window if any */
        ShapeWatch **prevPtr = &shapeWatchList;
        ShapeWatch *watch = shapeWatchList;
        while (watch) {
            if (watch->frameWin == frameWin) {
                *prevPtr = watch->next;
                Tcl_DecrRefCount(watch->callback);
                ckfree((char *)watch);
                break;
            }
            prevPtr = &watch->next;
            watch = watch->next;
        }

        /* If callback is empty, just remove the watch */
        int len;
        Tcl_GetStringFromObj(callback, &len);
        if (len == 0) {
            XShapeSelectInput(dpy, frameWin, 0);
            return TCL_OK;
        }

        /* Add new watch */
        watch = (ShapeWatch *)ckalloc(sizeof(ShapeWatch));
        watch->frameWin = frameWin;
        watch->interp = interp;
        watch->callback = callback;
        Tcl_IncrRefCount(callback);
        watch->next = shapeWatchList;
        shapeWatchList = watch;

        /* Request ShapeNotify events */
        XShapeSelectInput(dpy, frameWin, ShapeNotifyMask);

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
        ev.xclient.data.l[0] = 0;
        ev.xclient.data.l[1] = 0;
        ev.xclient.data.l[2] = 8;  /* _NET_WM_MOVERESIZE_MOVE */
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
    return SetHole(interp, window, ShapeInput, x, y, width, height);
}

critcl::cproc TkX::input_reset {
    Tcl_Interp* interp
    char* window
} ok {
    return ResetShape(interp, window, ShapeInput);
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
    return SetHole(interp, window, ShapeBounding, x, y, width, height);
}

critcl::cproc TkX::bounding_reset {
    Tcl_Interp* interp
    char* window
} ok {
    return ResetShape(interp, window, ShapeBounding);
}

# Shape notification - callback when shape changes
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
