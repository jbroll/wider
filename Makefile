# Makefile for wider

# Use local critcl with X11 fix
CRITCL_PATH = ../critcl/lib
CRITCL = TCLLIBPATH=$(CRITCL_PATH) critcl

all: xgetimage csd

# Build xgetimage using critcl
xgetimage: xgetimage.tcl
	$(CRITCL) -pkg -libdir lib xgetimage.tcl

# Build csd using critcl
csd: csd.tcl
	$(CRITCL) -pkg -libdir lib csd.tcl

clean:
	rm -rf lib/xgetimage lib/csd

.PHONY: all clean xgetimage csd
