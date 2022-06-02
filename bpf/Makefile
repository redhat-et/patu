
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


CGROUP2_PATH ?= $(shell mount | grep cgroup2 | awk '{print $$3}' | grep -v "^/host" | head -n 1)
ifeq ($(CGROUP2_PATH),)
$(error Please ensure that cgroup2 is enabled.)
endif

load-connect4: 
	sudo bpftool prog load patu_connect4.o $(PROG_MOUNT_PATH)/connect4

attach-connect4: 
	sudo bpftool cgroup attach $(CGROUP2_PATH) connect4 pinned $(PROG_MOUNT_PATH)/connect4

unload-connect4:
	sudo bpftool cgroup detach $(CGROUP2_PATH) connect4 pinned $(PROG_MOUNT_PATH)/connect4
	sudo rm $(PROG_MOUNT_PATH)/connect4

load-recvmsg4:
	sudo bpftool prog load patu_recvmsg4.o $(PROG_MOUNT_PATH)/recvmsg4

attach-recvmsg4: 
	sudo bpftool cgroup attach $(CGROUP2_PATH) recvmsg4 pinned $(PROG_MOUNT_PATH)/recvmsg4

unload-recvmsg4:
	sudo bpftool cgroup detach $(CGROUP2_PATH) recvmsg4 pinned $(PROG_MOUNT_PATH)/recvmsg4
	sudo rm $(PROG_MOUNT_PATH)/recvmsg4

load-sendmsg4:
	sudo bpftool prog load patu_sendmsg4.o $(PROG_MOUNT_PATH)/sendmsg4

attach-sendmsg4: 
	sudo bpftool cgroup attach $(CGROUP2_PATH) sendmsg4 pinned $(PROG_MOUNT_PATH)/sendmsg4

unload-sendmsg4:
	sudo bpftool cgroup detach $(CGROUP2_PATH) sendmsg4 pinned $(PROG_MOUNT_PATH)/sendmsg4
	sudo rm $(PROG_MOUNT_PATH)/sendmsg4

load: compile load-connect4 load-sendmsg4 load-recvmsg4
attach: attach-connect4 attach-sendmsg4 attach-recvmsg4
unload: unload-connect4 unload-sendmsg4 unload-recvmsg4 clean-obj