# Makefile for TkX

# Use local critcl with X11 fix
CRITCL_PATH = ../../critcl/lib
CRITCL = TCLLIBPATH=$(CRITCL_PATH) critcl

all: TkX

TkX: TkX.tcl
	$(CRITCL) -force -pkg -libdir lib TkX.tcl

clean:
	rm -rf lib/TkX

.PHONY: all clean TkX
