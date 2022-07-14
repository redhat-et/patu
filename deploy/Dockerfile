# Build patu app
FROM golang:1.18.1 as patu

WORKDIR /patu

ADD go.mod .
ADD go.sum .

ADD . .

RUN go mod download && \
    go build -ldflags "-s -w" -o ./dist/patu ./cmd/patu/cni/patu-cni.go && \
    go build -ldflags "-s -w" -o ./dist/patud ./cmd/patu/daemon/patu-daemon.go

# Build eBPF prog objects and bpftool
FROM ubuntu:22.04 as ebpf

ARG kernel

WORKDIR /
ARG DEBIAN_FRONTEND=noninteractive

COPY bpf bpf

RUN apt-get update && apt-get install -y git cmake clang make gcc python3 libncurses-dev gawk flex bison openssl \
    libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm && rm -rf /var/lib/apt/lists/* && make -C bpf compile && git clone -b v$kernel https://github.com/torvalds/linux.git --depth 1 && cd /linux/tools/bpf/bpftool && \
    make && make install  

# Generate final image with eBPF program objects and Patu app.
FROM ubuntu:22.04 as cni

WORKDIR /cni

RUN mkdir bpf && \
    apt-get update && \
    apt-get install --no-install-recommends -y make sudo libelf-dev && \
    apt-get autoremove -y && \
    apt-get clean -y && rm -rf /var/lib/apt/lists/*

COPY --from=ebpf bpf bpf
COPY --from=ebpf /usr/local/sbin/bpftool /usr/local/sbin/bpftool
COPY ./scripts/post-cni.sh /usr/local/sbin/
COPY --from=patu /patu/dist/ .

CMD /cni/patu