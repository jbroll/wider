# Makefile for wider

# Use local critcl with X11 fix
CRITCL_PATH = ../critcl/lib
CRITCL = TCLLIBPATH=$(CRITCL_PATH) critcl

all: xgetimage

# Build xgetimage using critcl
xgetimage: xgetimage_critcl.tcl
	$(CRITCL) -pkg -libdir lib xgetimage_critcl.tcl

clean:
	rm -rf lib/xgetimage_critcl

.PHONY: all clean xgetimage
