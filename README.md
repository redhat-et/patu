# [Patu](https://en.wikipedia.org/wiki/Patu_digua)

Lightweight networking solution for Container Orchestrators managing container lifecycle on resource constrained compute devices, such as Edge Devices.

## The Challenge

Containers to deploy workload on Edge devices is a new reality. Microshift, K3S, RHEL for Edge, RHEL for Automotive are some of the initiatives that RedHat is working actively to spread the reach of containers to the Edge devices. Generally most of the edge devices have limited compute resources (CPU and Memory), and users would prefer to use maximum compute resources to execute the workload deployed on the device.

Container networking stack is one of the major contenders for the device’s compute resources. As the packet traffic requires forwarding increases, it will cost more compute resources, and eventually workloads need to contend for compute resources with the networking stack to execute. This requires that the compute cost for per packet forwarding must be absolutely optimal to make most compute resources available for workload deployment.

Most of the large scale container orchestrators networking solutions (e.g kubernetes CNI) have a significant compute cost, because their architecture supports planet scale and the solutions are of very dynamic nature. The scope of these networking solutions is to provide networking within a single compute node as well as to provide networking across multiple compute nodes, and that makes these solutions more complex and compute intensive. On the contrary, Edge devices are mostly isolated devices running the workload that doesn’t require significant cross device communication.That significantly reduces the functional requirements for the networking solutions when it comes to edge devices.

Using the large scale container orchestrator CNI’s for edge devices incur unnecessary additional costs (mostly due to their complex control plane) on the critical compute resources of the edge device that can be used to deploy more workload on the device. Building a solution targeted to the networking requirements of the  edge devices can lead to simpler control and data plane solution that is less compute intensive.

## The Goal

With most of the existing container networking solutions, the packet from workload container needs to go through socket layer, tcp/ip layer and ethernet layer, and then it’s injected in the datapath running at the node level, that forwards the traffic to the destination workload container. At the destination workload container, the packet again needs to go through the networking layer again. This incurs the cost of encapsulation and decapsulation of the packet at each networking layer (socket, ip, ethernet), when the packet doesn’t even need to leave the node. This double traversal through the networking layers is unnecessary and costly when it comes to edge devices with limited compute resources.

This project is an attempt to build a CNI using a new operating system kernel technology named [eBPF](https://ebpf.io/what-is-ebpf) (extended Berkeley Packet Filter) with the goal to enable container networking with the optimum per packet compute cost. eBPF allows users to write kernel programs to intercept networking packets at multiple levels in the operating system networking stack. The high level idea of the CNI is to operate at the socket layer for the local traffic, leverage eBPF [xdp](https://developers.redhat.com/blog/2021/04/01/get-started-with-xdp) for ingress. Packet from the source container will be directly intercepted at the socket layer of the container and forwarded to the destination workload container's socket layer using the eBPF programs. This avoids multiple packet traversal through multiple networking layers, provides better latency and also requires less compute resources as packet doesn’t have to go through multiple layers of encapsulation and decapsulation. The control plane will enable the socket redirection across all the containers deployed within the worker node and will enable/disable socket redirection according to the container lifecycle.

## Deploying Patu

### Kubernetes

#### CNI Deployment:
Easiest way to play with Patu CNI is to deploy a single node kubernetes with `--pod-network-cidr=10.200.0.0/16`. Currently Patu CNI is tested with kernel version 5.15 (specifically Ubuntu 22.04), so we would recommend to create a VM with Ubuntu 22.04 distribution and install Kubernetes.

* Clone the patu repo.
* Apply the `patu.yaml` present in `deploy ` directory. 
  ``` 
  kubectl apply -f <path-to-patu-repo>/deploy/patu.yaml
  ```
* If you don't prefer to clone the repo, you can copy the yaml from `patu/deploy/patu.yaml` locally and apply it.

#### Verification:
Once you deploy patu, coredns pods should be in the running state and the pods should have IP address from the provide cidr.
On your kubernetes node, install the bpftool (ensure you install the tool for the kernel version currently running), and run the following command 
```
# bpftool prog list | grep patu
2927: cgroup_sock_addr  name patu_connect4  tag 226d8967214ee349  gpl
2931: cgroup_sock_addr  name patu_sendmsg4  tag d439a92f479811d9  gpl
2935: cgroup_sock_addr  name patu_recvmsg4  tag 06b0a415da0c17e5  gpl
2939: sock_ops  name patu_sockops  tag b800a2e173b7d69d  gpl
2943: sk_skb  name patu_skskb  tag 3dedccc91281ae84  gpl
```

#### Workload Deployment:
*Notes: Given that Patu CNI is targeted for single node, you need to remove the control-plane & master taint from the node to deploy any workload.*
```
kubectl taint nodes --all node-role.kubernetes.io/control-plane- node-role.kubernetes.io/master-
```

### Microshift
Coming Soon.



**This work is just incubated, so there are multiple open questions on the design of various CNI features (e.g Ingress, Network Policy), and we will address those as we progress.**
