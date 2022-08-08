#!/bin/bash
IP=$1
cat <<EOF | sudo tee /etc/crio/crio.conf
[crio.runtime] #<- table name
# Configuration
default_capabilities = [
    "CHOWN",
    "DAC_OVERRIDE",
    "FSETID",
    "FOWNER",
    "SETGID",
    "SETUID",
    "SETPCAP",
    "NET_BIND_SERVICE",
    "KILL",
    "NET_RAW",
]
EOF
systemctl restart crio.service
sleep 5s
kubectl create deployment pingtest --image=busybox --replicas=1 -- sleep infinity
PingPod=$(kubectl get pods --no-headers -o custom-columns=":metadata.name" | grep ping)
kubectl exec -it $PingPod -- ping $IP >> "/tmp/pingTest.txt"