/* TkX_shape.c - X11 Shape extension (click-through) */

#include "TkX.h"

/* ShapeNotify state - file-local statics */
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

static int MakeHoleRects(XRectangle *rects, int ww, int wh,
                         int hx, int hy, int hw, int hh) {
    int n = 0;
    if (hy > 0) {
        rects[n].x = 0; rects[n].y = 0;
        rects[n].width = ww; rects[n].height = hy;
        n++;
    }
    if (hy + hh < wh) {
        rects[n].x = 0; rects[n].y = hy + hh;
        rects[n].width = ww; rects[n].height = wh - (hy + hh);
        n++;
    }
    if (hx > 0) {
        rects[n].x = 0; rects[n].y = hy;
        rects[n].width = hx; rects[n].height = hh;
        n++;
    }
    if (hx + hw < ww) {
        rects[n].x = hx + hw; rects[n].y = hy;
        rects[n].width = ww - (hx + hw); rects[n].height = hh;
        n++;
    }
    return n;
}

int DoSetHole(Tcl_Interp *interp, const char *winPath,
              int kind, int hx, int hy, int hw, int hh) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    hx += wi.offX;
    hy += wi.offY;

    XRectangle rects[4];
    int nrects = MakeHoleRects(rects, wi.frameW, wi.frameH, hx, hy, hw, hh);

    XShapeCombineRectangles(wi.dpy, wi.frameWin, kind, 0, 0,
                            rects, nrects, ShapeSet, Unsorted);
    XFlush(wi.dpy);

    return TCL_OK;
}

int DoResetShape(Tcl_Interp *interp, const char *winPath, int kind) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    XShapeCombineMask(wi.dpy, wi.frameWin, kind, 0, 0, None, ShapeSet);
    XFlush(wi.dpy);

    return TCL_OK;
}

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

int DoShapeWatch(Tcl_Interp *interp, const char *winPath, Tcl_Obj *callback) {
    WinInfo wi;
    if (GetWinInfo(interp, winPath, &wi) != TCL_OK)
        return TCL_ERROR;

    if (shapeEventBase == 0) {
        if (!XShapeQueryExtension(wi.dpy, &shapeEventBase, &shapeErrorBase)) {
            Tcl_SetResult(interp, "Shape extension not available", TCL_STATIC);
            return TCL_ERROR;
        }
    }

    if (!shapeHandlerInstalled) {
        Tk_CreateGenericHandler(ShapeEventHandler, NULL);
        shapeHandlerInstalled = 1;
    }

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

    Tcl_Size len;
    Tcl_GetStringFromObj(callback, &len);
    if (len == 0) {
        XShapeSelectInput(wi.dpy, wi.frameWin, 0);
        return TCL_OK;
    }

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
