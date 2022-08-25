# [Patu](https://en.wikipedia.org/wiki/Patu_digua)

Patu is a lightweight networking solution for low footprint (CPU, Memory, Disk) container orchestrators targeted to manage resource constrained compute devices, such as Edge Devices.

# Motivation
It's an attempt to build CNI that is driven by the Edge related use cases and targeted for resource constraint deployment environment. Please read [here](./docs/Challange-and-goal.md) for more details about the challenge and the goal.

## Deploying Patu

Currently Patu CNI supports Pod-to-Pod networking and Cluster IP implementation. Pod-to-Pod networking is enabled through Bridge CNI with eBPF based socket redirection. Cluster IP support is provided through the [Kube Proxy Next Generation](https://github.com/kubernetes-sigs/kpng) eBPF based backend. If you want to use Patu CNI binary with the existing kube-proxy implementation, please refer to the instructions for specific cluster environment in `/deploy/` directory. Node Port service and Networking Policy support is currently under development and will land soon.


### Kubernetes
These instructions are to deploy Patu CNI with single node kubernetes, but if you are looking for detail instructions to setup Patu CNI to different environment (Kind, Microshift), please refer to the relevant documents in the `./deploy/` directory.


#### CNI Deployment
Easiest way to deploy and play with Patu CNI is to deploy a single node kubernetes with `--pod-network-cidr=10.200.0.0/16`. Currently Patu CNI is tested with kernel version 5.15 (specifically Ubuntu 22.04), so we would recommend to create a Ubuntu 22.04 VM/server as your playground.


* Install single node kubernetes

  <pre><code>
  kubeadm init  --upload-certs --pod-network-cidr=10.200.0.0/16 --v=6 --skip-phases=addon/kube-proxy
  </code></pre>
  
  Pod's state before CNI deployment

  <pre>
  # kubectl get pods -A
  NAMESPACE     NAME                                     READY   STATUS    RESTARTS      AGE
  kube-system   coredns-6d4b75cb6d-dhv78                 0/1     Pending   0             4s
  kube-system   coredns-6d4b75cb6d-wfwbh                 0/1     Pending   0             4s
  kube-system   etcd-kubernetes2204                      1/1     Running   715           15s
  kube-system   kube-apiserver-kubernetes2204            1/1     Running   2 (15m ago)   15s
  kube-system   kube-controller-manager-kubernetes2204   1/1     Running   2             15s
  kube-system   kube-scheduler-kubernetes2204            1/1     Running   2             15s
  </pre>

* Clone the patu repo.

  <pre><code>
  git clone https://github.com/redhat-et/patu.git
  </code></pre>

* Deploy the Patu CNI

  <pre><code>
  cd patu
  ./deploy/kubernetes/patu-installer apply all
  </code></pre>

  Installer will deploy the patu manifest as well as KPNG eBPF manifest. Pod's status after CNI deployment

  <pre>
  # kubectl get pods -A -o wide
  NAMESPACE     NAME                                     READY   STATUS    RESTARTS      AGE   IP                NODE             NOMINATED NODE   READINESS GATES
  <b>kube-system   coredns-6d4b75cb6d-dhv78                 1/1     Running   0             38m   10.200.0.3        kubernetes2204   <none>           <none></b>
  <b>kube-system   coredns-6d4b75cb6d-wfwbh                 1/1     Running   0             38m   10.200.0.2        kubernetes2204   <none>           <none></b>
  kube-system   etcd-kubernetes2204                      1/1     Running   715           38m   192.168.122.229   kubernetes2204   <none>           <none>
  <b>kube-system   kpng-sqwts                               3/3     Running   0             69s   192.168.122.229   kubernetes2204   <none>           <none></b>
  kube-system   kube-apiserver-kubernetes2204            1/1     Running   2 (54m ago)   38m   192.168.122.229   kubernetes2204   <none>           <none>
  kube-system   kube-controller-manager-kubernetes2204   1/1     Running   2             38m   192.168.122.229   kubernetes2204   <none>           <none>
  kube-system   kube-scheduler-kubernetes2204            1/1     Running   2             38m   192.168.122.229   kubernetes2204   <none>           <none>
  <b>kube-system   patu-jtw85                               1/1     Running   0             70s   192.168.122.229   kubernetes2204   <none>           <none></b>
  </pre>

#### Verification
Once you deploy patu, coredns pods should be in the running state and should have IP address from the provide cidr.
On your kubernetes node, install the bpftool (ensure you install the tool for the kernel version currently running), and run the following command 

<pre>
#bpftool prog list
...
...
393: cgroup_sock_addr  name <b>sock4_connect</b>  tag 59372233301aea77  gpl
	loaded_at 2022-08-22T19:08:10+0000  uid 0
	xlated 1000B  jited 625B  memlock 4096B  map_ids 28,29
	btf_id 102
397: sock_ops  name <b>patu_sockops</b>  tag a11096f06c210cab  gpl
	loaded_at 2022-08-22T19:08:11+0000  uid 0
	xlated 1248B  jited 727B  memlock 4096B  map_ids 31
	btf_id 108
401: sk_msg  name <b>patu_skmsg</b>  tag 6736c050a3a25de2  gpl
	loaded_at 2022-08-22T19:08:12+0000  uid 0
	xlated 952B  jited 595B  memlock 4096B  map_ids 31
	btf_id 114
405: cgroup_sock_addr  name <b>patu_sendmsg4</b>  tag d439a92f479811d9  gpl
	loaded_at 2022-08-22T19:08:13+0000  uid 0
	xlated 336B  jited 203B  memlock 4096B
	btf_id 120
409: cgroup_sock_addr  name <b>patu_recvmsg4</b>  tag 06b0a415da0c17e5  gpl
	loaded_at 2022-08-22T19:08:13+0000  uid 0
	xlated 336B  jited 203B  memlock 4096B
	btf_id 126
  ...
  ...
  </pre>

#### CNI Cleanup

  <pre><code>
  ./deploy/kubernetes/patu-installer delete all
  </code></pre>

  It will remove all the resources deployed through Patu and KPNG manifest. 

#### Workload Deployment
*Notes: Given that Patu CNI is targeted for single node, you need to remove the control-plane & master taint from the node to deploy any workload.*
<pre><code>
kubectl taint nodes --all node-role.kubernetes.io/control-plane- node-role.kubernetes.io/master-
</code></pre>

### Supported Kubernetes Platforms

- [kind](./deploy/kind/README.md) - Local Kind Kubernetes clusters primarily designed for testing Kubernetes
- [Kubernetes](./deploy/kubernetes/README.md) - Single Node Kubernetes cluster
- [Microshift](./deploy/microshift/README.md) - OpenShift/Kubernetes optimized for the device edge


### Note
**This project work is in incubation state, so there are multiple open questions on the design of various CNI features (e.g Ingress, Network Policy), and we will address those as we progress.**
