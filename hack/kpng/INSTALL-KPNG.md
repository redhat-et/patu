# Steps to deploy KPNG with patu

## What is KPNG?

The Kubernetes Proxy NG a new design of kube-proxy. Using the eBPF backend here, out of the available backends.

## Steps:

1. Ensure kubernetes cluster has been setup without kube-proxy  
    `kubeadm init  --upload-certs --pod-network-cidr=10.200.0.0/16 --v=6 --skip-phases=addon/kube-proxy`  
    Or can disable kube-proxy, using kubectl to delete the kube-proxy daemonset from kube-system namespace  
    `kubectl delete daemonsets -n kube-system kube-proxy`
2. Deploy patu using deploy/patu.yaml  
    `kubectl apply -f \<path-to-patu.yaml\>/patu.yaml`
3. Ensure status - All pods except coredns pods should be in running and ready state. Coredns pods should have IP from patu CIDR and  should be running, but not ready.
4. Build KPNG  
    Repository: https://github.com/kubernetes-sigs/kpng  
    Cmd: `docker build -t \<imagename:tag\> -f Dockerfile .`  
        e.g. `docker build -t kpng:test -f Dockerfile .`
5. Set the following variables:  
    - NAMESPACE="kube-system"  
    - CONFIG_MAP_NAME="kpng"  
    - CONFIG_MAP_NAME="kpng"  
    - CLUSTER_ROLE_NAME="system:node-proxier"  
    - CLUSTER_ROLE_BINDING_NAME="kpng"  
6. Commands concerning pre-requisites:  
    - `kubectl create serviceaccount --namespace ${NAMESPACE} ${SERVICE_ACCOUNT_NAME}`  

    - `kubectl create clusterrolebinding ${CLUSTER_ROLE_BINDING_NAME} --clusterrole=${CLUSTER_ROLE_NAME} --serviceaccount=${NAMESPACE}:${SERVICE_ACCOUNT_NAME}` 
    
    - `kubectl create configmap ${CONFIG_MAP_NAME} --namespace ${NAMESPACE}  --from-file /etc/kubernetes/admin.conf`  
7. Label node:  
    `kubectl label node <NODE-NAME> kube-proxy=kpng`  
8. Deploy KPNG:  
    Replace \<imagename:tag\> in kpngebpf.yml  
    `kubectl apply -f kpngebpf.yml`  

## Testing setup:
1. `kubectl create -f https://k8s.io/examples/application/deployment.yaml`
2. `kubectl expose deployment nginx-deployment --type=ClusterIP`
3. `kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot`

Expected: Curl to the exposed ip of the nginx-deployment service (obtained using `kubectl get svc -A -o wide`) should work from the tmp-shell.