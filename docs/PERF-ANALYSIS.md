# Steps used for performance analysis of Flannel, PATU with Kubernetes

The tests have been done on 2 core CPU, 4G RAM VM with the ubuntu 22.04 OS, 5.15.0-43-generic being the kernel version.  


## NMON  

To have a detailed view of the CPU, memory consumption throughout a test- we can use `nmon`.Nmon is a performance monitor for Linux, which dumps the data of concern in a file; while can be viewed in form of graphs in a html page.    
1. To install nmon (install on k8s control-plane noe) - `apt install nmon`.    
2. Install latest zip of nmonchart from http://nmon.sourceforge.net/pmwiki.php?n=Site.Nmonchart . This is used to convert the data collected using nmon into a viewable html page. This can be downloaded even outside the machine containing the cluster.    


### Execution steps  
1. On the control-plane node, run `nmon -h`. Form the command according to your preference- e.g. `nmon -fTDMNU -s 2 -c 100`  
Note: If not sure about the count of snapshots, denoted by `-c`; give a big number as its value, maybe around 10000. Can terminate the nmon process later on using the process id from `ps -ef | grep "nmon -f"`  


This command will create a file named `$NodeName_$timestamp.nmon` with all the statistics selected in the command and place them in the current directory. This file after termination of folder has to be fed to the Nmonchart.

2. Extract the Nmonchart on any machine. Place the .nmon file on the same machine.  
Run the following command- `<Path to extracted nmonchart directory>/nmonchart <nmon-file> <output-file>.html`  
This will create a HTML file with all the data presented in graphical format, which can be rendered in any browser.


## Usage of Top command

To have precise information about any fluctuations in terms of CPU consumption and which processes are play for the same- `top` command can be used. To facilitate this, a small script has been created that can be triggered before scaling the pods or before doing any load test to see which process is consuming the most CPU resources.  

The data from this script can be used in tandem to nmon results for better clarity.    

```
#!/bin/bash
timestamp=$(date +%d-%m-%Y_%H-%M-%S)
filename="topdata_$timestamp"
while true
do
	echo "$(date +%d-%m-%Y_%H-%M-%S)" >> $filename
	top -b -n 1 >> $filename
	echo "------------------------------------------------------------------------------------------">> $filename
	sleep 1
done
```

## Description about scenario based test scripts

1. During the preliminary testing, ../scripts/scaleTest.sh script has been used to test the extent upto which a certain deployment can be scaled with the given constraints and to inflict changes to observe effect of scaling on CNI resource consumption. 
2. Script called ../scripts/impartLoad.sh is used to continuously curl to a certain IP and get the responses iterated into a file. This file helps to determine the number of calls served successfully with HTTP response code 200; and hence calculate statistics like calls handled per second.   
This script can be run as `../scripts/impartLoad.sh <IP of concern> <Number>`. Second argument enables this script to handle multiple threads concurrently. If the script is triggered say 3 times, all three threads will put in their data in separate files.  
3. To calculate the latency of response of `ping` while testing pos-to-pod communication, ../scripts/pingLatency.sh has been created. This script, creates a pod in the default namespace with ping capability and then triggers a continuous ping and forwards that data into a file. This script when terminated, feeds in the average latency value in the file as well.  


## iperf3 testing

### Execution steps
1. Create a new namespace  
`kubectl create namespace iperf-test`
2. Create server pod    
```
rm -f pod-iperf-server.yaml 
cat >> pod-iperf-server.yaml <<EOL
apiVersion: v1
kind: Pod
metadata:
  name: iperf-server
  namespace: iperf-test
spec:
  containers:
  - name: net-toolbox
    image: quay.io/wcaban/net-toolbox:latest
    ports:
      - containerPort: 5201
        name: iperf
        protocol: TCP
EOL
```


Execute the following commands:
```
kubectl delete -f pod-iperf-server.yaml
kubectl create -f pod-iperf-server.yaml
```

3. Create client Pod
```
export IPERF_SERVER=`oc get pods iperf-server -n iperf-test -o=jsonpath="{['status.podIP']}"`
```


```    command:
      - iperf3
      - "-c"
      - "$IPERF_SERVER"
      - "-V"
      - "-t"
      - "0"
      - "--forceflush"
rm -f pod-iperf-client.yaml 
cat >> pod-iperf-client.yaml <<EOL
apiVersion: v1
kind: Pod
metadata:
  name: iperf-client
  namespace: iperf-test
spec:
  containers:
  - name: net-toolbox
    image: quay.io/wcaban/net-toolbox:latest
EOL
```


Execute the following commands:
```
kubectl delete -f pod-iperf-client.yaml
kubectl create -f pod-iperf-client.yaml
```

4. Execute following commands:
```
export IPERF_SERVER=`oc get pods iperf-server -n iperf-test -o=jsonpath="{['status.podIP']}"`
kubectl exec -it iperf-server -n iperf-test -- iperf3 -s -B 0.0.0.0 -V -i 1 >> serverstats.txt
kubectl exec -it iperf-client -n iperf-test -- iperf3 -c "$IPERF_SERVER" -V -t 0 >> clientstats.txt
```

The files serverstats.txt and clientstats.txt will have the transfer and the bitrate details.  

## Sample Test strategy:
1. Have the cluster of concern up and ready  
2. Trigger nmon and top script as instructed above  
3. Trigger scalePodTest.sh  
4. Post completion of step 3, Impart internal or external load using impartLoad.sh - trigger it 10 to 12 times i.e. have 10 to 12 active threads  
5. Wait for 5 to 10 mins  
6. Terminate the nmon and top script processes  
7. Collect data using iperf3  
