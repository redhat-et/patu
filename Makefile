# Image building related targets
KERNEL?=5.15

build-image:
	export KERNEL=$(KERNEL); ./scripts/build-image.sh

clean-image:
	./scripts/clean-image.sh

# Go code related targets
go-build:
	go build -ldflags "-s -w" -o ./dist/patu ./cmd/patu/cni/patu-cni.go
	go build -ldflags "-s -w" -o ./dist/patud ./cmd/patu/daemon/patu-daemon.go

go-lint:
	golangci-lint run --go=1.17

go-clean:
	rm -Rf ./dist
	
pre-commit-checks: go-lint go-build go-clean
	make -C bpf pre-commit-checks

