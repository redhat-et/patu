
CC=clang
CFLAGS=-O2 -g  -Wall -target bpf -I/usr/include/$(shell uname -m)-linux-gnu
PROG_MOUNT_PATH=/sys/fs/bpf

MACROS:=
DEBUG ?=

ifeq ($(DEBUG),1)
    MACROS:= $(MACROS) -DDEBUG
endif

TARGETS=patu_connect4.o patu_recvmsg4.o patu_sendmsg4.o patu_skmsg.o patu_sockops.o

%.o: %.c
	$(CC) $(CFLAGS) $(MACROS) -c $< -o $@

compile: $(TARGETS)

clean-obj:
	[ -f patu_connect4.c ] && sudo rm -f $(TARGETS)

