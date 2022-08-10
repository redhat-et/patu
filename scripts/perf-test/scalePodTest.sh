##
# Copyright © 2022 Authors of Patu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#!/bin/sh
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