KERNEL?=5.7 #Build image for default 5.7 kernel.

build-image:
	export KERNEL=$(KERNEL)
	./scripts/build-image.sh

clean-image:
	./scripts/clean-image.sh

go-lint:
	golangci-lint run

c-lint:
	clang-format --Werror -n bpf/*.c bpf/include/helpers/*.h