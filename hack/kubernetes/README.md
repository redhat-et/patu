# Steps to deploy KPNG with Patu using Kubernetes

## What is KPNG?

The Kubernetes Proxy NG a new design of kube-proxy. Using the eBPF backend here, out of the available backends.

## Steps:

### Using the installer script

#### Necessary steps:  
Install kubernetes without kube-proxy  | Remove kube-proxy  
1. Ensure kubernetes cluster has been setup without kube-proxy  
    `kubeadm init  --upload-certs --pod-network-cidr=10.200.0.0/16 --v=6 --skip-phases=addon/kube-proxy`  
    Or can disable kube-proxy, using kubectl to delete the kube-proxy daemonset from kube-system namespace  
    `kubectl delete daemonsets -n kube-system kube-proxy`  
2. Clone the following repository on the kubernetes control plane node  
   Link: https://github.com/redhat-et/patu.git  


#### Install PATU CNI  
1. Deploy Patu  
    Execute this command: `<path-to-patu-repo>/patu/scripts/installer/patu-installer apply cni`  
    Ensure the script doesn't result in any errors.   
2. Ensure status - All pods should be in running state. Coredns pods should have IP from patu CIDR as mentioned in <path-to-patu-repo>/patu/deploy/patu.yaml, and should be running but not ready



#### Install KPNG  
1. Deploy kpng  
    Execute this command: `<path-to-patu-repo>/patu/scripts/installer/patu-installer apply kpng`   
    Ensure the script doesn't result in any errors.  
2. Ensure status - All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers running and ready 


#### Remove KPNG  
1. Execute this command: `<path-to-patu-repo>/patu/scripts/installer/patu-installer delete kpng`  
   Ensure the script doesn't result in any errors.


#### Remove PATU CNI
1. Execute this command: `<path-to-patu-repo>/patu/scripts/installer/patu-installer delete cni`    
   Ensure the script doesn't result in any errors.  


#### INSTALL-ALL:  
1. Deploy patu and kpng  
    Execute this command: `<path-to-patu-repo>/patu/scripts/installer/patu-installer apply all`   
    Ensure the script doesn't result in any errors.  
2. Ensure status - All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers running and ready  



#### REMOVE-ALL:  
1. Execute this command: `<path-to-patu-repo>/patu/scripts/installer/patu-installer delete all`    
   Ensure the script doesn't result in any errors.  


### Manual Instructions:

#### Install Patu CNI   
1. `kubectl apply -f <path-to-patu-repo>/patu/deploy/patu.yaml`  
2. Ensure status - All pods should be in running state. Coredns pods should have IP from patu CIDR as mentioned in patu.yaml, and should be running but not ready


#### Install KPNG  
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
5. Deploy kpng:
    `kubectl apply -f <path-to-patu-repo>/patu/hack.kubernetes/kpngebpf.yaml`  
6. Ensure status - All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers running and ready  


#### Remove KPNG  
1. Remove KPNG Daemon set, service account, cluster role+ binding:  
    `kubectl delete -f <path-to-patu-repo>/patu/hack.kubernetes/kpngebpf.yaml`  
2. Remove configmap:  
    `kubectl delete cm kpng -n kube-system`
3. Extract node name:  
    ```
    (ip addr | awk '/inet/{print $2}' | awk -F/ '{print $1}') > /tmp/internal_ip.txt  
    local_node=$(kubectl get node -o wide | grep -f /tmp/internal_ip.txt | awk '{print $1}')
    ```
4. Remove label from node:  
    `kubectl label node $local_node kube-proxy-`


#### Remove PATU
1. Remove PATU Daemon set, service account, cluster role+ binding:  
    `kubectl delete -f <path-to-patu-repo>/patu/deploy/patu.yaml` 
    

## Testing setup:
1. `kubectl create -f https://k8s.io/examples/application/deployment.yaml`
2. `kubectl expose deployment nginx-deployment --type=ClusterIP`
3. `kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot`

Expected: Curl to the exposed ip of the nginx-deployment service (obtained using `kubectl get svc -A -o wide`) should work from the tmp-shell.
Coredns pods should be in ready state.