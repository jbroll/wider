# xgetimage.tcl
package require Critcl 3.3.0

Critcl::ccode {
#include <X11/Xlib.h>
#include <string.h>
#include <stdlib.h>

/* Global X Display */
static Display *dpy = NULL;

int XGetImage_Init(Tcl_Interp *interp) {
    if (!dpy) {
        dpy = XOpenDisplay(NULL);
        if (!dpy) {
            Tcl_SetResult(interp, "Cannot open X display", TCL_STATIC);
            return TCL_ERROR;
        }
    }
    return TCL_OK;
}

/* Tcl command: xgetimage root|window x y width height */
int XGetImage_Cmd(ClientData cd, Tcl_Interp *interp, int argc, const char *argv[]) {
    if (argc != 6) {
        Tcl_WrongNumArgs(interp, 1, argv, "root|window x y width height");
        return TCL_ERROR;
    }

    Window win;
    if (strcmp(argv[1], "root") == 0) {
        win = DefaultRootWindow(dpy);
    } else {
        /* parse as integer window ID */
        if (Tcl_GetInt(interp, argv[1], (int *)&win) != TCL_OK) {
            return TCL_ERROR;
        }
    }

    int x, y, w, h;
    if (Tcl_GetInt(interp, argv[2], &x) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetInt(interp, argv[3], &y) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetInt(interp, argv[4], &w) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetInt(interp, argv[5], &h) != TCL_OK) return TCL_ERROR;

    XImage *img = XGetImage(dpy, win, x, y, (unsigned int)w, (unsigned int)h, AllPlanes, ZPixmap);
    if (!img) {
        Tcl_SetResult(interp, "XGetImage failed", TCL_STATIC);
        return TCL_ERROR;
    }

    /* Convert to Tcl byte array in RGB order */
    int bytes_per_pixel = img->bits_per_pixel / 8;
    Tcl_Obj *listObj = Tcl_NewListObj(0, NULL);

    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            unsigned long pixel = XGetPixel(img, i, j);
            unsigned char r = (pixel & img->red_mask) >> 16;
            unsigned char g = (pixel & img->green_mask) >> 8;
            unsigned char b = (pixel & img->blue_mask);
            Tcl_ListObjAppendElement(interp, listObj, Tcl_NewByteArrayObj((unsigned char[]){r,g,b}, 3));
        }
    }

    XDestroyImage(img);
    Tcl_SetObjResult(interp, listObj);
    return TCL_OK;
}
}

Critcl::cproc xgetimage {args} -body XGetImage_Cmd -init XGetImage_Init
