/* TkX.h - X11 extensions for Tk
 *
 * Common types, constants, and function declarations
 */

#ifndef TKX_H
#define TKX_H

#include <tcl.h>
#include <tk.h>
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

/* ========== Atom Cache ========== */

typedef struct {
    Display *dpy;
    Atom NET_CLIENT_LIST;
    Atom NET_WM_DESKTOP;
    Atom NET_WM_NAME;
    Atom NET_WM_PID;
    Atom NET_WM_STATE;
    Atom NET_WM_STATE_ABOVE;
    Atom NET_ACTIVE_WINDOW;
    Atom NET_WM_MOVERESIZE;
    Atom NET_FRAME_EXTENTS;
    Atom MOTIF_WM_HINTS;
    Atom WM_WINDOW_ROLE;
    Atom UTF8_STRING;
} AtomCache;

extern AtomCache Atoms;

/* Helper macro: get display or return error */
#define REQUIRE_DISPLAY(interp, dpy) \
    Display *dpy = GetDisplay(interp); \
    if (!dpy) { \
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC); \
        return TCL_ERROR; \
    }

/* ========== Common Types ========== */

typedef struct {
    Display *dpy;
    Window tkWin;
    Window frameWin;
    int offX, offY;
    int frameW, frameH;
} WinInfo;

typedef struct {
    unsigned long flags;
    unsigned long functions;
    unsigned long decorations;
    long          input_mode;
    unsigned long status;
} MotifWmHints;

#define MWM_HINTS_DECORATIONS (1L << 1)

/* ========== Core Helpers (TkX_core.c) ========== */

void InitAtoms(Display *dpy);
Display* GetDisplay(Tcl_Interp *interp);
Window WalkToFrame(Display *dpy, Window win, int *offX, int *offY);
int GetWinInfo(Tcl_Interp *interp, const char *winPath, WinInfo *info);
int dir_to_edge(const char *dir);
Visual* FindARGBVisual(Display *dpy, int screen, int *depth_out);
void SendClientMessage(Display *dpy, Window win, Atom msgType,
                       long d0, long d1, long d2, long d3, long d4);

/* ========== Capture (TkX_capture.c) ========== */

int DoCapture(Tcl_Interp *interp, const char *photoName,
              const char *winArg, int x, int y, int w, int h);

/* ========== Shape (TkX_shape.c) ========== */

int DoSetHole(Tcl_Interp *interp, const char *winPath,
              int kind, int hx, int hy, int hw, int hh);
int DoResetShape(Tcl_Interp *interp, const char *winPath, int kind);
int DoShapeWatch(Tcl_Interp *interp, const char *winPath, Tcl_Obj *callback);

/* ========== CSD (TkX_csd.c) ========== */

int DoNodecor(Tcl_Interp *interp, const char *winPath);
int DoMove(Tcl_Interp *interp, const char *winPath);
int DoResize(Tcl_Interp *interp, const char *winPath, const char *direction);

/* ========== RGBA (TkX_rgba.c) ========== */

int DoRGBACheck(Tcl_Interp *interp);
int DoClearRegion(Tcl_Interp *interp, const char *winPath,
                  int x, int y, int w, int h);
int DoCreateARGBOverlay(Tcl_Interp *interp, const char *winPath);
int DoCreateARGBChild(Tcl_Interp *interp, const char *winPath,
                      int x, int y, int w, int h);
int DoCreateARGBWindow(Tcl_Interp *interp, int x, int y, int w, int h);
int DoARGBFillRect(Tcl_Interp *interp, long winId,
                   int x, int y, int w, int h,
                   int r, int g, int b, int a);
int DoMapWindow(Tcl_Interp *interp, long winId);

/* ========== Window Management (TkX_window.c) ========== */

int DoMoveResizeWindow(Tcl_Interp *interp, long winId,
                       int x, int y, int w, int h);
int DoDestroyWindow(Tcl_Interp *interp, long winId);
int DoReparentWindow(Tcl_Interp *interp, long childId,
                     long parentId, int x, int y);
int DoMoveWindow(Tcl_Interp *interp, long winId, int x, int y, int w, int h);
int DoWindowOffset(Tcl_Interp *interp, long winId);
int DoGetActiveWindow(Tcl_Interp *interp);
int DoSetDesktop(Tcl_Interp *interp, long winId, int desktop);
int DoWindowState(Tcl_Interp *interp, long winId, const char *action,
                  const char *prop1, const char *prop2);
int DoSetProperty(Tcl_Interp *interp, long winId,
                  const char *propName, const char *value);
int DoResizeId(Tcl_Interp *interp, long winId, const char *direction);
int DoMoveId(Tcl_Interp *interp, long winId);
int DoActivateId(Tcl_Interp *interp, long winId);

/* ========== Query (TkX_query.c) ========== */

int DoListWindows(Tcl_Interp *interp);
int DoGetProps(Tcl_Interp *interp, long winId);

#endif /* TKX_H */
