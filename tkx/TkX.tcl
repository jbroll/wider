# TkX.tcl - X11 extensions for Tk
#
# Build: critcl -pkg TkX.tcl
#
# C implementation is organized into separate files:
#   TkX.h          - Common types, constants, and function declarations
#   TkX_core.c     - Common helper functions
#   TkX_capture.c  - Screen/window capture
#   TkX_shape.c    - X11 Shape extension (click-through)
#   TkX_csd.c      - Client-side decorations, WM move/resize
#   TkX_rgba.c     - ARGB windows, transparency
#   TkX_window.c   - Window management
#   TkX_query.c    - Window listing and properties

package require Tcl 9.0
package require critcl 3.2

critcl::tcl 9.1
critcl::tk

critcl::clibraries -lX11 -lXext -lXrender

# Include header and C source files
critcl::cheaders TkX.h
critcl::csources TkX_core.c TkX_capture.c TkX_shape.c TkX_csd.c TkX_rgba.c TkX_window.c TkX_query.c

# Include TkX.h in generated code
critcl::ccode {
    #include "TkX.h"
}

# ========== Capture ==========

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

# ========== Shape ==========

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

critcl::cproc TkX::shape_watch {
    Tcl_Interp* interp
    char* window
    Tcl_Obj* callback
} ok {
    return DoShapeWatch(interp, window, callback);
}

# ========== CSD ==========

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

# ========== RGBA ==========

critcl::cproc TkX::rgba_available {
    Tcl_Interp* interp
} ok {
    return DoRGBACheck(interp);
}

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

critcl::cproc TkX::rgba_overlay {
    Tcl_Interp* interp
    char* window
} ok {
    return DoCreateARGBOverlay(interp, window);
}

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

critcl::cproc TkX::rgba_window {
    Tcl_Interp* interp
    int x
    int y
    int width
    int height
} ok {
    return DoCreateARGBWindow(interp, x, y, width, height);
}

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

critcl::cproc TkX::window_map {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoMapWindow(interp, window_id);
}

critcl::cproc TkX::set_transparent_bg {
    Tcl_Interp* interp
    char* window
} ok {
    WinInfo wi;
    if (GetWinInfo(interp, window, &wi) != TCL_OK)
        return TCL_ERROR;

    XSetWindowBackground(wi.dpy, wi.tkWin, 0);
    XClearWindow(wi.dpy, wi.tkWin);
    XFlush(wi.dpy);

    return TCL_OK;
}

# ========== Window Management ==========

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

critcl::cproc TkX::window_destroy {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoDestroyWindow(interp, window_id);
}

critcl::cproc TkX::reparent {
    Tcl_Interp* interp
    long child_id
    long parent_id
    int x
    int y
} ok {
    return DoReparentWindow(interp, child_id, parent_id, x, y);
}

critcl::cproc TkX::resize_id {
    Tcl_Interp* interp
    long window_id
    char* direction
} ok {
    return DoResizeId(interp, window_id, direction);
}

critcl::cproc TkX::move_id {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoMoveId(interp, window_id);
}

critcl::cproc TkX::activate_id {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoActivateId(interp, window_id);
}

critcl::cproc TkX::window_offset {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoWindowOffset(interp, window_id);
}

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

critcl::cproc TkX::active_window {
    Tcl_Interp* interp
} ok {
    return DoGetActiveWindow(interp);
}

critcl::cproc TkX::set_desktop {
    Tcl_Interp* interp
    long window_id
    int desktop
} ok {
    return DoSetDesktop(interp, window_id, desktop);
}

critcl::cproc TkX::window_state {
    Tcl_Interp* interp
    long window_id
    char* action
    char* prop1
    char* prop2
} ok {
    return DoWindowState(interp, window_id, action, prop1, prop2);
}

critcl::cproc TkX::set_property {
    Tcl_Interp* interp
    long window_id
    char* property
    char* value
} ok {
    return DoSetProperty(interp, window_id, property, value);
}

# ========== Query ==========

critcl::cproc TkX::list_windows {
    Tcl_Interp* interp
} ok {
    return DoListWindows(interp);
}

critcl::cproc TkX::get_props {
    Tcl_Interp* interp
    long window_id
} ok {
    return DoGetProps(interp, window_id);
}

critcl::cproc TkX::pointer_state {
    Tcl_Interp* interp
} ok {
    return DoPointerState(interp);
}

package provide TkX 1.0
