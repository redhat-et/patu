#!/bin/bash
kubectl apply -f ../docs/deployment.yml
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 10
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 28
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 5
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 30
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 20
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 2
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 28
sleep 5s
kubectl expose deployment nginx-deployment --type=ClusterIP
sleep 5s
#kubectl expose deploy nginx-deployment --type=NodePort --port=80 --name nginx-service
kubectl scale deploy/nginx-deployment --replicas 2
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 30
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 10
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 5
sleep 5s
kubectl scale deploy/nginx-deployment --replicas 28
sleep 5s