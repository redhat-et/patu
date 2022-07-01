make -C /cni/bpf -k detach
make -C /cni/bpf -k unload

rm /opt/cni/bin/patu
rm /etc/cni/net.d/20-patu.conflist 