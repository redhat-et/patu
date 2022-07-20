# Hacking with kind

### Kind Deployment

* Install [kind](https://kind.sigs.k8s.io/docs/user/quick-start/)

```shell
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.11.1/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

* Start a single node kind cluster

```shell
kind create cluster
```

* Clone and start Patu

```shell
git clone https://github.com/redhat-et/patu.git
cd patu
kubectl apply -f deploy/patu.yaml
    serviceaccount/patu created
    clusterrole.rbac.authorization.k8s.io/patu created
    clusterrolebinding.rbac.authorization.k8s.io/patu created
    configmap/patu-cni-conf created
    daemonset.apps/patu created
```

* Verify the Patu pod starts

```shell
fedora@ip-10-10-0-76:~/e2e$ kubectl get pods --all-namespaces
NAMESPACE            NAME                                         READY   STATUS    RESTARTS   AGE
kube-system          coredns-558bd4d5db-59jg6                     1/1     Running   0          21h
kube-system          coredns-558bd4d5db-8gfqz                     1/1     Running   0          21h
kube-system          etcd-kind-control-plane                      1/1     Running   0          21h
kube-system          kindnet-9r8tb                                1/1     Running   0          21h
kube-system          kube-apiserver-kind-control-plane            1/1     Running   0          21h
kube-system          kube-controller-manager-kind-control-plane   1/1     Running   0          21h
kube-system          kube-proxy-bh4w2                             1/1     Running   0          21h
kube-system          kube-scheduler-kind-control-plane            1/1     Running   0          21h
kube-system          patu-z2x4w                                   1/1     Running   0          20h
local-path-storage   local-path-provisioner-547f784dff-vzrnm      1/1     Running   0          21h
```