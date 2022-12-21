#!/bin/sh
make -C ../bpf/ clean-obj
make -C ../bpf/ compile
PATU_POD=`kubectl get pods -n kube-system | grep patu | awk '{print $1}'`
echo "Patu pod name is : "$PATU_POD
kubectl exec -it $PATU_POD -c patu -n kube-system -- ls -lrt ./bpf/
kubectl cp ../bpf kube-system/$PATU_POD:/cni/ -c patu
kubectl exec -it $PATU_POD -c patu -n kube-system -- ls -lrt ./bpf/
kubectl exec -it $PATU_POD -c patu -n kube-system -- make -C bpf detach-sk-msg detach-sockops unload-sk-msg unload-sockops
kubectl exec -it $PATU_POD -c patu -n kube-system -- make -C bpf load-sockops load-sk-msg attach-sockops attach-sk-msg