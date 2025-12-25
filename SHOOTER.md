

Use xgetimage.tck
Use csd.tcl

Init Tk window iconified
Set CSD for no decorations as GTk does
XGetImage root 
Set root pixmap as  canvas background

Deiconify image
Fade areas outside the capture rectangle with alpha .3?
Draw capture rectangle as white with handles

On RET - withdraw app, wait for delay, and recapture live root.
