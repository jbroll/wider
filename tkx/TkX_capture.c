/* TkX_capture.c - Screen/window capture */

#include "TkX.h"

int DoCapture(Tcl_Interp *interp, const char *photoName,
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
