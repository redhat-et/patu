# Image building related targets
KERNEL?=5.15 #Build image for default 5.7 kernel.

build-image:
	export KERNEL=$(KERNEL)
	./scripts/build-image.sh

clean-image:
	./scripts/clean-image.sh

# Go code related targets
go-build:
	go build -ldflags "-s -w" -o ./dist/patu ./cmd/patu/patu.go

go-lint:
	golangci-lint run

go-clean:
	rm -Rf ./dist
	
pre-commit-checks: go-lint go-build go-clean
	make -C bpf pre-commit-checks

