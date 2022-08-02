# Steps to deploy KPNG with Patu using Kubernetes

## What is KPNG?

The Kubernetes Proxy NG a new design of kube-proxy. Using the eBPF backend here, out of the available backends.

## Steps:

### Install kubernetes without kube-proxy  | Remove kube-proxy
1. Ensure kubernetes cluster has been setup without kube-proxy  
    `kubeadm init  --upload-certs --pod-network-cidr=10.200.0.0/16 --v=6 --skip-phases=addon/kube-proxy`  
    Or can disable kube-proxy, using kubectl to delete the kube-proxy daemonset from kube-system namespace  
    `kubectl delete daemonsets -n kube-system kube-proxy`  

   

### Install Patu CNI  
1. Copy `../../deploy/patu.yaml` to a directory, say `dir` on the server  
2. `kubectl apply -f <path-to-dir>/dir/patu.yaml`  
3. Ensure status - All pods should be in running state. Coredns pods should have IP from patu CIDR as mentioned in patu.yaml, and should be running but not ready



### Install KPNG  
1. Build KPNG  
    Repository: https://github.com/kubernetes-sigs/kpng  
    Cmd: `docker build -t <imagename:tag> -f Dockerfile .`    
        e.g. `docker build -t kpng:test -f Dockerfile .`  
2. Replace the placeholder `<imagename:tag>` with the selected imagename:tag in `./kpngebpf.yaml`  

#### Individual instructions  
1. Extract node name:  
    ```
    (ip addr | awk '/inet/{print $2}' | awk -F/ '{print $1}') > /tmp/internal_ip.txt  
    local_node=$(kubectl get node -o wide | grep -f /tmp/internal_ip.txt | awk '{print $1}')
    ```
2. Remove taints concerning control-plane, master:  
    `kubectl taint nodes $local_node node-role.kubernetes.io/master:NoSchedule- node-role.kubernetes.io/control-plane:NoSchedule-`  
3. Label node:  
    `kubectl label node $local_node kube-proxy=kpng`  
4. Create configmap:  
    `kubectl create configmap kpng --namespace kube-system --from-file /etc/kubernetes/admin.conf`  
5. Copy`./kpngebpf.yaml` to a directory, say `dir` on the server  
6. Deploy kpng:
    `kubectl apply -f <path-to-dir>/dir/kpngebpf.yaml`  
7. Ensure status - All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers running and ready  

#### Using script  
1. Copy `./kpngebpf.yaml`, `../../scripts/kpng-installer` to a directory, say `dir` on the server  
2. Deploy kpng  
    `<path-to-dir>/dir/kpng-installer apply`  
    Ensure the script doesn't result in any errors. 
3. Ensure status - All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers running and ready  



### Remove KPNG  

#### Individual instructions  
1. Copy `./kpngebpf.yaml` to a directory, say `dir` on the server  
2. Remove KPNG Daemon set, service account, cluster role+ binding:  
    `kubectl delete -f <path-to-dir>/dir/kpngebpf.yaml`  
3. Remove configmap:  
    `kubectl delete cm kpng -n kube-system`
4. Remove label from node:  
    `kubectl label node $local_node kube-proxy-`

#### Using script  
1. Copy `./kpngebpf.yaml`, `../../scripts/kpng-installer` to a directory, say `dir` on the server  
2. Delete patu and kpng  
    `<path-to-dir>/dir/kpng-installer delete`  
    Ensure the script doesn't result in any errors.



### Remove PATU
1. Copy `../../deploy/patu.yaml` to a directory, say `dir` on the server  
2. Remove PATU Daemon set, service account, cluster role+ binding:  
    `kubectl delete -f <path-to-dir>/dir/patu.yaml`  



### INSTALL-ALL:  
1. Copy `../../deploy/patu.yaml`, `./kpngebpf.yaml`, `../../scripts/patu-installer` to a directory, say `dir` on the server  
2. Deploy patu and kpng  
    `<path-to-dir>/dir/patu-installer apply`  
    Ensure the script doesn't result in any errors. 
3. Ensure status - All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers running and ready  



### REMOVE-ALL:  
1. Copy `../../scripts/patu-installer` to a directory, say `dir` on the server  
2. Delete patu and kpng  
    `<path-to-dir>/dir/patu-installer delete`  
    Ensure the script doesn't result in any errors.


## Testing setup:
1. `kubectl create -f https://k8s.io/examples/application/deployment.yaml`
2. `kubectl expose deployment nginx-deployment --type=ClusterIP`
3. `kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot`

Expected: Curl to the exposed ip of the nginx-deployment service (obtained using `kubectl get svc -A -o wide`) should work from the tmp-shell.
Coredns pods should be in ready state.