/*
 * xgetimage.c - Capture X11 window/root to Tk photo image
 *
 * Usage from Tcl: xgetimage::capture <photo> root|<window_id> x y width height
 *
 * Compile: gcc -shared -fPIC -o xgetimage.so xgetimage.c \
 *          -I/usr/include -lX11 -ltcl8.6 -ltk8.6
 */

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <tcl.h>
#include <tk.h>
#include <stdlib.h>
#include <string.h>

static int XGetImageCmd(ClientData clientData, Tcl_Interp *interp,
                        int objc, Tcl_Obj *const objv[]) {
    if (objc != 7) {
        Tcl_WrongNumArgs(interp, 1, objv, "photo root|window x y width height");
        return TCL_ERROR;
    }

    /* Get the photo image handle */
    const char *photoName = Tcl_GetString(objv[1]);
    Tk_PhotoHandle photo = Tk_FindPhoto(interp, photoName);
    if (!photo) {
        Tcl_SetObjResult(interp, Tcl_ObjPrintf("photo \"%s\" not found", photoName));
        return TCL_ERROR;
    }

    /* Get display from Tk */
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "No Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);

    /* Parse window argument */
    Window win;
    const char *winArg = Tcl_GetString(objv[2]);
    if (strcmp(winArg, "root") == 0) {
        win = DefaultRootWindow(dpy);
    } else {
        long winId;
        if (Tcl_GetLongFromObj(interp, objv[2], &winId) != TCL_OK) {
            return TCL_ERROR;
        }
        win = (Window)winId;
    }

    /* Parse geometry */
    int x, y, w, h;
    if (Tcl_GetIntFromObj(interp, objv[3], &x) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetIntFromObj(interp, objv[4], &y) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetIntFromObj(interp, objv[5], &w) != TCL_OK) return TCL_ERROR;
    if (Tcl_GetIntFromObj(interp, objv[6], &h) != TCL_OK) return TCL_ERROR;

    /* Capture the image */
    XImage *img = XGetImage(dpy, win, x, y, (unsigned)w, (unsigned)h, AllPlanes, ZPixmap);
    if (!img) {
        Tcl_SetResult(interp, "XGetImage failed", TCL_STATIC);
        return TCL_ERROR;
    }

    /* Resize photo to match */
    Tk_PhotoSetSize(interp, photo, w, h);

    /* Allocate RGBA buffer */
    unsigned char *data = (unsigned char *)ckalloc(w * h * 4);
    if (!data) {
        XDestroyImage(img);
        Tcl_SetResult(interp, "Memory allocation failed", TCL_STATIC);
        return TCL_ERROR;
    }

    /* Convert XImage to RGBA */
    unsigned char *p = data;
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            unsigned long pixel = XGetPixel(img, i, j);
            *p++ = (pixel >> 16) & 0xff;  /* R */
            *p++ = (pixel >> 8) & 0xff;   /* G */
            *p++ = pixel & 0xff;          /* B */
            *p++ = 255;                   /* A */
        }
    }
    XDestroyImage(img);

    /* Write to photo */
    Tk_PhotoImageBlock block;
    block.pixelPtr = data;
    block.width = w;
    block.height = h;
    block.pitch = w * 4;
    block.pixelSize = 4;
    block.offset[0] = 0;  /* R */
    block.offset[1] = 1;  /* G */
    block.offset[2] = 2;  /* B */
    block.offset[3] = 3;  /* A */

    Tk_PhotoPutBlock(interp, photo, &block, 0, 0, w, h, TK_PHOTO_COMPOSITE_SET);
    ckfree((char *)data);

    return TCL_OK;
}

int Xgetimage_Init(Tcl_Interp *interp) {
    if (Tcl_InitStubs(interp, "8.6", 0) == NULL) return TCL_ERROR;
    if (Tk_InitStubs(interp, "8.6", 0) == NULL) return TCL_ERROR;

    Tcl_CreateObjCommand(interp, "xgetimage::capture", XGetImageCmd, NULL, NULL);
    Tcl_PkgProvide(interp, "xgetimage", "0.1");
    return TCL_OK;
}
