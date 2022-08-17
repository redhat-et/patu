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

package e2e

import (
	"context"
	"fmt"
	"net"
	"os/exec"
	"strings"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/kubernetes/test/e2e/framework"
	admissionapi "k8s.io/pod-security-admission/api"
)

// newPrivelegedTestFramework creates a new ginkgo framework
func newPrivelegedTestFramework(basename string) *framework.Framework {
	f := framework.NewDefaultFramework(basename)
	f.NamespacePodSecurityEnforceLevel = admissionapi.LevelPrivileged
	return f
}

// runCommand runs the cmd and returns the combined stdout and stderr
func runCommand(cmd ...string) (string, error) {
	output, err := exec.Command(cmd[0], cmd[1:]...).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("failed to run %q: %s (%s)", strings.Join(cmd, " "), err, output)
	}
	return string(output), nil
}

// getPodAddress Get the IP address of a pod in the specified namespace
func getPodAddress(podName, namespace string) string {
	podIP, err := framework.RunKubectl(namespace, "get", "pods", podName, "--template={{.status.podIP}}")
	if err != nil {
		framework.Failf("Unable to retrieve the IP for pod %s %v", podName, err)
	}
	return podIP
}

// curlConnectivity Curls a target address and port
func curlConnectivity(ip, port string, timeout int) []string {
	curl := fmt.Sprintf("curl -g --connect-timeout %v http://%s", timeout, net.JoinHostPort(ip, port))
	cmd := []string{"/bin/sh", "-c", curl}
	return cmd
}

// getBpfList retrieve the bpf program list
func getBpfList() string {
	bpfOut, err := runCommand("sudo", "bpftool", "prog", "list")
	if err != nil {
		framework.Failf("failed to run bpftool cmd: %v", err)
	}
	return bpfOut
}

func checkDaemonStatus(f *framework.Framework, dsName, ns string) error {
	ds, err := f.ClientSet.AppsV1().DaemonSets(ns).Get(context.TODO(), dsName, metav1.GetOptions{})
	if err != nil {
		return fmt.Errorf("Could not get daemon set from v1")
	}
	desired, scheduled, ready := ds.Status.DesiredNumberScheduled, ds.Status.CurrentNumberScheduled, ds.Status.NumberReady
	if desired != scheduled && desired != ready {
		return fmt.Errorf("Error in daemon status. DesiredScheduled: %d, CurrentScheduled: %d, Ready: %d", desired, scheduled, ready)
	}
	return nil
}
