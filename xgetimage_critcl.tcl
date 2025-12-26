# xgetimage_critcl.tcl - Capture X11 window/root to Tk photo image
#
# Usage from Tcl: xgetimage::capture <photo> root|<window_id> x y width height
#
# Build: critcl -pkg xgetimage_critcl.tcl

package require Tcl 8.6
package require critcl 3.2

critcl::tcl 8.6
critcl::tk

critcl::clibraries -lX11

critcl::ccode {
    #include <X11/Xlib.h>
    #include <X11/Xutil.h>
    #include <stdlib.h>
    #include <string.h>

    static int DoCapture(Tcl_Interp *interp, const char *photoName,
                         const char *winArg, int x, int y, int w, int h) {
        /* Get the photo image handle */
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
}

critcl::cproc xgetimage::capture {
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

package provide xgetimage 0.2
