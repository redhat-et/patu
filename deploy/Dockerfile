# Build patu app
FROM golang:1.18.1 as patu

WORKDIR /patu

ADD go.mod .
ADD go.sum .

RUN go mod download

ADD . .

RUN go build -ldflags "-s -w" -o ./dist/patu ./cmd/patu/patu.go

# Build eBPF prog objects and bpftool
FROM ubuntu:22.04 as ebpf

ARG kernel

WORKDIR /
ARG DEBIAN_FRONTEND=noninteractive

COPY bpf bpf

RUN apt-get update && apt-get install -y git cmake clang make gcc python3 libncurses-dev gawk flex bison openssl \
    libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm

RUN grep cgroup /proc/filesystems
RUN uname -a
RUN clang --version

#RUN make -C bpf compile

RUN git clone -b v$kernel https://github.com/torvalds/linux.git --depth 1

RUN cd /linux/tools/bpf/bpftool && \
    make && make install  

# Generate final image with eBPF program objects and Patu app.
FROM ubuntu:22.04 as cni

WORKDIR /cni

RUN mkdir bpf
COPY --from=ebpf bpf bpf
COPY --from=ebpf /usr/local/sbin/bpftool /usr/local/sbin/bpftool
COPY --from=patu /patu/dist/patu patu
RUN uname -r && apt-get update && apt-get install --no-install-recommends -y make sudo libelf-dev clang && apt-get autoremove -y && apt-get clean -y

CMD /cni/patu