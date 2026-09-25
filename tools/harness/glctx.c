// Creates a legacy (compatibility profile) GLX context on an X display (e.g. Xvfb)
#include <X11/Xlib.h>
#include <GL/glx.h>
#include <stdio.h>
static Display *dpy; static Window win; static GLXContext ctx;
int init_ctx(int w, int h) {
    dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "no display\n"); return 1; }
    int attr[] = { GLX_RGBA, GLX_DEPTH_SIZE, 24, GLX_DOUBLEBUFFER, None };
    XVisualInfo *vi = glXChooseVisual(dpy, DefaultScreen(dpy), attr);
    if (!vi) { fprintf(stderr, "no visual\n"); return 2; }
    Colormap cmap = XCreateColormap(dpy, RootWindow(dpy, vi->screen), vi->visual, AllocNone);
    XSetWindowAttributes swa; swa.colormap = cmap; swa.event_mask = 0;
    win = XCreateWindow(dpy, RootWindow(dpy, vi->screen), 0, 0, w, h, 0, vi->depth, InputOutput, vi->visual, CWColormap | CWEventMask, &swa);
    ctx = glXCreateContext(dpy, vi, NULL, GL_TRUE);
    if (!ctx) { fprintf(stderr, "no ctx\n"); return 3; }
    glXMakeCurrent(dpy, win, ctx);
    return 0;
}
