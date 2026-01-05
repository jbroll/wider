/* TkX_query.c - Window listing and properties */

#include "TkX.h"

int DoListWindows(Tcl_Interp *interp) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window root = DefaultRootWindow(dpy);

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

        XClassHint classHint = {0};
        char *className = "";
        if (XGetClassHint(dpy, win, &classHint)) {
            className = classHint.res_class ? classHint.res_class : "";
        }

        Window child;
        int absX, absY;
        XTranslateCoordinates(dpy, win, root, 0, 0, &absX, &absY, &child);

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

int DoGetProps(Tcl_Interp *interp, long winId) {
    Tk_Window tkwin = Tk_MainWindow(interp);
    if (!tkwin) {
        Tcl_SetResult(interp, "no Tk main window", TCL_STATIC);
        return TCL_ERROR;
    }
    Display *dpy = Tk_Display(tkwin);
    Window win = (Window)winId;

    Tcl_Obj *result = Tcl_NewDictObj();

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
