# Makefile for wider

CC = gcc
CFLAGS = -shared -fPIC -I/usr/include
LDFLAGS = -lX11 -ltcl8.6 -ltk8.6

all: xgetimage.so

xgetimage.so: xgetimage.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f xgetimage.so

.PHONY: all clean
