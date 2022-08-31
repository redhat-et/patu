# Deploy Patu as a Kubernetes CNI

Patu deployment consist of CNI binary and [KPNG](https://github.com/kubernetes-sigs/kpng) eBPF backend.

#### Deploy Kubernetes without kube-proxy

If you didn't deploy the cluster yet, you can skip the kube-proxy addon phase during the cluster deployment

<pre><code>
kubeadm init  --upload-certs --pod-network-cidr=10.200.0.0/16 --v=6 --skip-phases=addon/kube-proxy
</code></pre>

If you already have a running cluster, remove the existing deployed CNI (if any), and remove the existing kube-proxy

<pre><code>
kubectl delete daemonsets -n kube-system kube-proxy
</code></pre>

#### Clone Patu Repository

<pre><code>
git clone https://github.com/redhat-et/patu.git
</code></pre>

#### Kubernetes Kubeconfig

By default, kubeadm places kubeconfig file at `/etc/kubernetes/admin.conf` with root permissions. The installer defaults to that location as well. Specify a custom kubeconfig location with the following example passing `KUBECONFIG` as an environmental variable:

<pre><code>
KUBECONFIG=~/.kube/config ./deploy/kubernetes/patu-installer apply all
</code></pre>

#### Install PATU CNI Binary
<pre><code>
./deploy/kubernetes/patu-installer apply cni
</code></pre>
 
 Ensure all pods are in running state. Coredns pods should have IP from patu CIDR as mentioned in `./deploy/patu.yaml`, and should be running but not in `Ready` state because Cluster-Ip is yet not enabled. 

#### Install KPNG  eBPF backend
<pre><code>
./deploy/kubernetes/patu-installer apply kpng
</code></pre>

All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers `Running` and `Ready` state.

#### Remove KPNG  
<pre><code>
./deploy/kubernetes/patu-installer delete kpng
</code></pre>

#### Remove PATU CNI
<pre><code>
./deploy/kubernetes/patu-installer delete cni
</code></pre>


#### Install full Patu stack (CNI Binary and KPNG eBPF backend)
<pre><code>
./deploy/kubernetes/patu-installer apply all
</code></pre>

#### Uninstall full Patu stack (CNI Binary and KPNG eBPF backend)
<pre><code>
./deploy/kubernetes/patu-installer delete all
</code></pre>


### Manual Instructions:

#### Install Patu CNI   
1. Deploy Patu CNI from the patu directory 
   <pre><code>
   `kubectl apply -f ./deploy/patu.yaml`  
   </code></pre>
2. Ensure status - All pods should be in running state. Coredns pods should have IP from patu CIDR as mentioned in patu.yaml, and should be running but not ready


#### Install KPNG  
1. Extract node name:  
    <pre><code>
    local_node=$(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o custom-columns=NAME:.metadata.name --no-headers)
    </code></pre>
2. Remove taints concerning control-plane, master:  
    <pre><code>kubectl taint nodes $local_node node-role.kubernetes.io/master:NoSchedule- node-role.kubernetes.io/control-plane:NoSchedule- </code></pre> 
3. Label node: 
   <pre><code> kubectl label node $local_node kube-proxy=kpng </code></pre>
4. Create configmap:  
    <pre><code> kubectl create configmap kpng --namespace kube-system --from-file /etc/kubernetes/admin.conf </code></pre>  
5. Deploy kpng from the patu directory:
    <pre><code>kubectl apply -f ./deploy/kpngebpf.yaml</code></pre>
6. Ensure status - All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers running and ready  


#### Remove KPNG  
1. Remove KPNG Daemon set, service account, cluster role+ binding:  
    <pre><code>kubectl delete -f ./deploy/kpngebpf.yaml</code></pre>  
2. Remove configmap:  
    <pre><code>kubectl delete cm kpng -n kube-system</code></pre>
3. Extract node name:  
    <pre><code>
    local_node=$(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o custom-columns=NAME:.metadata.name --no-headers)
    </code></pre>
4. Remove label from node:  
    <pre><code>kubectl label node $local_node kube-proxy-</code></pre>


#### Remove PATU
1. Remove PATU Daemon set, service account, cluster role+ binding:  
    <pre><code>kubectl delete -f ./deploy/patu.yaml</code></pre>
    

## Testing setup:

<pre><code>
kubectl create -f https://k8s.io/examples/application/deployment.yaml
kubectl expose deployment nginx-deployment --type=ClusterIP
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot
</code></pre>

Expected: Curl to the exposed ip of the nginx-deployment service (obtained using `kubectl get svc -A -o wide`) should work from the tmp-shell.
Coredns pods should be in ready state.