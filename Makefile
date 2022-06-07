KERNEL?=5.7 #Build image for default 5.7 kernel.

build-image:
	export KERNEL=$(KERNEL)
	./scripts/build-image.sh

clean-image:
	./scripts/clean-image.sh
