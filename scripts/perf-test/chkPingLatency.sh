#
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
IP=$1
cat <<EOF | sudo tee /etc/crio/crio.conf
[crio.runtime] #<- table name
# Configuration
default_capabilities = [
    "CHOWN",
    "DAC_OVERRIDE",
    "FSETID",
    "FOWNER",
    "SETGID",
    "SETUID",
    "SETPCAP",
    "NET_BIND_SERVICE",
    "KILL",
    "NET_RAW",
]
EOF
systemctl restart crio.service
sleep 5s
kubectl create deployment pingtest --image=busybox --replicas=1 -- sleep infinity
PingPod=$(kubectl get pods --no-headers -o custom-columns=":metadata.name" | grep ping)
kubectl exec -it $PingPod -- ping $IP >> "/tmp/pingTest.txt"