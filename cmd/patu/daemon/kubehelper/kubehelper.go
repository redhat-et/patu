/*
 * Copyright © 2022 Authors of Patu
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package kubehelper

import (
	"context"
	"encoding/json"
	"fmt"
	"net"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

const (
	patuNamespace  = "kube-system"
	patuConfigMap  = "patu-cni-conf"
	patuConfigFile = "patu-cni-conf.json"
)

type IPNet net.IPNet

type CniConf struct {
	IPAM IPAMConfig `json:"ipam,omitempty"`
}

type IPAMConfig struct {
	Type   string     `json:"type"`
	Ranges []RangeSet `json:"ranges"`
}

type RangeSet []Range

type Range struct {
	Subnet string `json:"subnet"`
}

func GetKubeClient() (clientset *kubernetes.Clientset) {
	// creates the in-cluster config
	config, err := rest.InClusterConfig()
	if err != nil {
		panic(err.Error())
	}
	// creates the clientset
	clientset, err = kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}
	return
}

func GetSubnetFromConfig(clientset *kubernetes.Clientset) (net.IP, *net.IPNet, error) {
	configMap, err := clientset.CoreV1().ConfigMaps(patuNamespace).Get(context.TODO(), patuConfigMap, metav1.GetOptions{})
	if err != nil {
		panic(err.Error())
	}
	if configMap == nil {
		return nil, nil, fmt.Errorf("ConfigMap %s not found in the namespace %s", patuConfigMap, patuNamespace)
	} else {
		var cmFile string
		if value, ok := configMap.Data[patuConfigFile]; ok {
			cmFile = value
		}

		config := &CniConf{}
		if err := json.Unmarshal([]byte(cmFile), config); err != nil {
			return nil, nil, fmt.Errorf("Error in unmarshalling %v", err)
		}

		//Currently patu supports only one range.
		subnet := (config.IPAM.Ranges[0][0]).Subnet
		ip, mask, err := net.ParseCIDR(subnet)
		if err != nil {
			return ip, mask, fmt.Errorf("Failed to parse subnet CIDR %s", subnet)
		}
		return ip, mask, err
	}
}
