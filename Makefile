# Makefile for wider

# Use local critcl with X11 fix
CRITCL_PATH = ../critcl/lib
CRITCL = TCLLIBPATH=$(CRITCL_PATH) critcl

all: TkX

# Build TkX (combined X11 extensions) using critcl
TkX: TkX.tcl
	$(CRITCL) -pkg -libdir lib TkX.tcl

clean:
	rm -rf lib/TkX

.PHONY: all clean TkX
