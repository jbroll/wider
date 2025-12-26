# Makefile for wider

CC = gcc
CFLAGS = -shared -fPIC -I/usr/include
LDFLAGS = -lX11 -ltcl8.6 -ltk8.6

# Use local critcl with X11 fix
CRITCL_PATH = ../critcl/lib
CRITCL = TCLLIBPATH=$(CRITCL_PATH) critcl

all: xgetimage.so

# Build using gcc directly
xgetimage.so: xgetimage.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# Build using critcl as a package
xgetimage-pkg: xgetimage_critcl.tcl
	$(CRITCL) -pkg xgetimage_critcl.tcl

clean:
	rm -f xgetimage.so
	rm -rf lib

.PHONY: all clean xgetimage-pkg
