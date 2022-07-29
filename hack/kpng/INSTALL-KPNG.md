# Steps to deploy KPNG with patu

## What is KPNG?

The Kubernetes Proxy NG a new design of kube-proxy. Using the eBPF backend here, out of the available backends.

## Steps:

1. Ensure kubernetes cluster has been setup without kube-proxy  
    `kubeadm init  --upload-certs --pod-network-cidr=10.200.0.0/16 --v=6 --skip-phases=addon/kube-proxy`  
    Or can disable kube-proxy, using kubectl to delete the kube-proxy daemonset from kube-system namespace  
    `kubectl delete daemonsets -n kube-system kube-proxy`  
2. Build KPNG  
    Repository: https://github.com/kubernetes-sigs/kpng  
    Cmd: `docker build -t \<imagename:tag\> -f Dockerfile .`    
        e.g. `docker build -t kpng:test -f Dockerfile .`  
3. Replace the placeholder `\<imagename:tag\>` with the selected imagename:tag in `./kpngebpf.yaml`  


### If PATU hasn't been deployed yet:  

4. Copy `../../deploy/patu.yaml`, `./kpngebpf.yaml`, `./patu` to a directory, say `dir` on the server  
5. Deploy patu and kpng  
    `\<path-to-dir\>/dir/patu apply`  
    Ensure the script doesn't result in any errors. 
6. Ensure status - All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers running and ready  


### If PATU has been already deployed:  

4. Copy `./kpngebpf.yaml`, `./kpng` to a directory, say `dir` on the server  
5. Deploy kpng  
    `\<path-to-dir\>/dir/kpng apply`  
    Ensure the script doesn't result in any errors. 
6. Ensure status - All pods should be in running and ready state. Coredns pods should have IP from patu CIDR, KPNG pod should have 3 containers running and ready  


## To remove PATU and KPNG:  

1. Copy `./patu` to a directory, say `dir` on the server  
2. Delete patu and kpng  
    `\<path-to-dir\>/dir/patu delete`  
    Ensure the script doesn't result in any errors. 


## To remove KPNG:  

1. Copy `./kpng` to a directory, say `dir` on the server  
2. Delete patu and kpng  
    `\<path-to-dir\>/dir/kpng delete`  
    Ensure the script doesn't result in any errors. 


## Testing setup:
1. `kubectl create -f https://k8s.io/examples/application/deployment.yaml`
2. `kubectl expose deployment nginx-deployment --type=ClusterIP`
3. `kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot`

Expected: Curl to the exposed ip of the nginx-deployment service (obtained using `kubectl get svc -A -o wide`) should work from the tmp-shell.
Coredns pods should be in ready state.