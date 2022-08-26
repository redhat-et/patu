# Deploy Patu as a Kind Cluster CNI

### Deploy Kind Cluster

* Install [kind](https://kind.sigs.k8s.io/docs/user/quick-start/)

<pre><code>
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
</code></pre>

* Start a single node kind cluster without a default CNI and without kube-proxy.

<pre><code>
kind create cluster --config=./deploy/kind/kind.yaml
</code></pre>

If you would like to deploy only PATU CNI binary and use the default kube-proxy deployment, you can update the `./deloy/kind/kind.yaml` and remove `kubeProxyMode: "none"`.

### Install Patu CNI (with KPNG eBPF backend)

* Clone and start Patu

<pre><code>
git clone https://github.com/redhat-et/patu.git
cd patu
./deploy/kind/patu-installer apply all
</code></pre>

You should see log messages similar to the following on stdout

<pre>
# ./deploy/kind/patu-installer apply all
Installing Patu for kind cluster : patu
serviceaccount/patu created
clusterrole.rbac.authorization.k8s.io/patu created
clusterrolebinding.rbac.authorization.k8s.io/patu created
configmap/patu-cni-conf created
daemonset.apps/patu created
node/patu-control-plane labeled
configmap/kpng created
serviceaccount/kpng created
clusterrolebinding.rbac.authorization.k8s.io/kpng created
daemonset.apps/kpng created
[ PASSED ] Successfully installed Patu on Kind cluster : patu
</pre>

* Verify the Patu pods (Patu CNI + KPNG) are up and in Ready State. After deploying CNI, coredns pods should be in ready state and should get IP address from the CNI CIDR range.

<pre>
#kubectl get pods -A
NAMESPACE            NAME                                         READY   STATUS    RESTARTS          AGE
kube-system          coredns-6d4b75cb6d-gr5g9                     1/1     Running   0                 25h
kube-system          coredns-6d4b75cb6d-jlx8l                     1/1     Running   0                 27h
kube-system          etcd-patu-control-plane                      1/1     Running   0                 27h
kube-system          kpng-xhj7g                                   3/3     Running   0                 47s <----
kube-system          kube-apiserver-patu-control-plane            1/1     Running   0                 27h
kube-system          kube-controller-manager-patu-control-plane   1/1     Running   0                 27h
kube-system          kube-scheduler-patu-control-plane            1/1     Running   0                 27h
kube-system          patu-lpdqs                                   1/1     Running   0                 48s <----
local-path-storage   local-path-provisioner-9cd9bd544-tw4g5       1/1     Running   245 (3h22m ago)   27h
</pre>

### Uninstall Patu CNI

<pre><code>
./deploy/kind/patu-installer delete all
</code></pre>

You should see log messages similar to the following on stdout

<pre>
# ./deploy/kind/patu-installer delete all
Uninstalling Patu for kind cluster : patu
serviceaccount "kpng" deleted
clusterrolebinding.rbac.authorization.k8s.io "kpng" deleted
daemonset.apps "kpng" deleted
configmap "kpng" deleted
node/patu-control-plane unlabeled
serviceaccount "patu" deleted
clusterrole.rbac.authorization.k8s.io "patu" deleted
clusterrolebinding.rbac.authorization.k8s.io "patu" deleted
configmap "patu-cni-conf" deleted
daemonset.apps "patu" deleted
[ PASSED ] Successfully uninstalled Patu from Kind cluster : patu
</pre>


### Advance Deployment Instructions


*  Installing Patu CNI with existing kube-proxy deployemt. Make sure to  remove `kubeProxyMode: "none"` from `./deloy/kind/kind.yaml` before deploying kind cluster.
 
 <pre><code>
 ./deploy/kind/patu-installer apply cni
 </code></pre>

 * Uninstalling Patu CNI 
 
 <pre><code>
 ./deploy/kind/patu-installer delete cni
 </code></pre>

* Installing KPNG eBPF backend with the default `kindnet` CNI. Make sure to remove `disableDefaultCNI: true` from `./deloy/kind/kind.yaml` before deploying kind cluster.

 <pre><code>
 ./deploy/kind/patu-installer apply kpng
 </code></pre>

* Uninstalling KPNG eBPF backend 
 
 <pre><code>
 ./deploy/kind/patu-installer delete kpng
 </code></pre>
