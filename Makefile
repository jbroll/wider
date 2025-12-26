# Makefile for wider

# Use local critcl with X11 fix
CRITCL_PATH = ../critcl/lib
CRITCL = TCLLIBPATH=$(CRITCL_PATH) critcl

all: xgetimage csd

# Build xgetimage using critcl
xgetimage: xgetimage_critcl.tcl
	$(CRITCL) -pkg -libdir lib xgetimage_critcl.tcl

# Build csd using critcl
csd: csd_critcl.tcl
	$(CRITCL) -pkg -libdir lib csd_critcl.tcl

clean:
	rm -rf lib/xgetimage_critcl lib/csd_critcl

.PHONY: all clean xgetimage csd
