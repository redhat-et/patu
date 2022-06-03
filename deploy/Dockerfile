FROM golang:1.18.1 as patu

WORKDIR /patu

ADD go.mod .
ADD go.sum .

RUN go mod download

ADD . .

RUN go build -ldflags "-s -w" -o ./dist/patu ./cmd/patu/patu.go

FROM ubuntu:21.10

WORKDIR /cni

RUN apt update && apt install -y make sudo libelf-dev clang iproute2 ethtool
COPY bpf bpf
COPY --from=patu /patu/dist/patu patu

CMD /cni/patu