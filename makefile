# Makefile para compilar o Sauron em macOS ou Linux

CC      = clang
SRC     = sauron.m
OUT     = sauron

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
    # macOS
    CFLAGS  = -fobjc-arc
    LDFLAGS = -framework Foundation -lz
else
    # Linux
    CFLAGS  = -fobjc-arc $(shell gnustep-config --objc-flags)
    LDFLAGS = -lgnustep-base -lz
endif

all:
	$(CC) $(CFLAGS) $(SRC) $(LDFLAGS) -o $(OUT)

clean:
	rm -f $(OUT)
