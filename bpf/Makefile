# This is top level makefile. Compile and load related targets are present in their 
# separate makefile. Reason for separation is to ensure that compiling doesn't fail
# while building the image through github workers and it don't have cgroup enabled.
# cgroup2 enable check is required for eBPF prog loading, and we don't load these
# object while building the image.
PROG_MOUNT_PATH=/sys/fs/bpf

compile:
	make -f Makefile.compile compile

lint:
	make -f Makefile.compile lint

clean-obj:
	make -f Makefile.compile clean-obj

CGROUP2_PATH ?= $(shell cat /proc/filesystems| grep cgroup2)
ifeq ($(CGROUP2_PATH),)
$(error Please ensure that cgroup2 is enabled.)
endif
	
# Maps related targets
load-sockops-redir-map:
	make -f Makefile.load load-sockops-redir-map
unload-sockops-redir-map:
	make -f Makefile.load unload-sockops-redir-map
load-cni-config-map:
	make -f Makefile.load load-cni-config-map
unload-cni-config-map:
	make -f Makefile.load unload-cni-config-map

load-maps: load-sockops-redir-map load-cni-config-map
unload-maps: unload-sockops-redir-map unload-cni-config-map unload-all-maps

# Passthrough targets.
load-sockops:
	make -f Makefile.load load-sockops
attach-sockops:
	make -f Makefile.load attach-sockops
detach-sockops:
	make -f Makefile.load detach-sockops
unload-sockops:
	make -f Makefile.load unload-sockops

load-sk-skb:
	make -f Makefile.load load-sk-skb
attach-sk-skb:
	make -f Makefile.load attach-sk-skb
detach-sk-skb:
	make -f Makefile.load detach-sk-skb
unload-sk-skb:
	make -f Makefile.load unload-sk-skb

load-sk-msg:
	make -f Makefile.load load-sk-msg
attach-sk-msg:
	make -f Makefile.load attach-sk-msg
detach-sk-msg:
	make -f Makefile.load detach-sk-msg
unload-sk-msg:
	make -f Makefile.load unload-sk-msg

load-prog: load-sockops load-sk-msg # load-sk-skb
attach-prog: attach-sockops attach-sk-msg # attach-sk-skb
detach-prog: detach-sk-msg detach-sockops # detach-sk-skb
unload-prog: unload-sk-msg unload-sockops # unload-sk-skb

pre-commit-checks: lint compile