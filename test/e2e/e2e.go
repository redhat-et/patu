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
	"os/exec"
	"strings"

	"github.com/onsi/ginkgo"
	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/kubernetes/test/e2e/framework"
	e2edeployment "k8s.io/kubernetes/test/e2e/framework/deployment"
)

const (
	patuSockOps        = "patu_sockops"
	patuSkMsg          = "patu_skmsg"
	patuCgroupSockSend = "patu_sendmsg4"
	patuCgroupSockRecv = "patu_recvmsg4"
)

// runCommand runs the cmd and returns the combined stdout and stderr
func runCommand(cmd ...string) (string, error) {
	output, err := exec.Command(cmd[0], cmd[1:]...).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("failed to run %q: %s (%s)", strings.Join(cmd, " "), err, output)
	}
	return string(output), nil
}

// This test validates that the patu bpf programs are loaded
/* This test does the following:
   1. Verify sock_ops named patu_sockops program is loaded
   2. Verify sk_msg program named patu_skmsg is loaded
   3. Verify cgroup_sock_addr program named patu_sendmsg4 is loaded
   4. Verify cgroup_sock_addr program named patu_recvmsg4 is loaded
*/
var _ = ginkgo.Describe("Validate patu ebpf programs are loaded", func() {
	var bpfOut string
	var err error
	ginkgo.BeforeEach(func() {
		bpfOut, err = runCommand("sudo", "bpftool", "prog", "list")
		if err != nil {
			framework.Failf("failed to run bpftool cmd: %v", err)
		}
	})

	ginkgo.It("Verify Patu is loaded properly by examining the loaded bpf programs", func() {

		ginkgo.By("1. Verify sock_ops named patu_sockops program is loaded")
		if !strings.Contains(bpfOut, patuSockOps) {
			framework.Failf("The program %s was not found\n", patuSockOps)
		}

		ginkgo.By("2. Verify sk_msg program named patu_skmsg is loaded")
		if !strings.Contains(bpfOut, patuSkMsg) {
			framework.Failf("The program %s was not found\n", patuSkMsg)
		}

		ginkgo.By("3. Verify cgroup_sock_addr program named patu_sendmsg4 is loaded")
		if !strings.Contains(bpfOut, patuCgroupSockSend) {
			framework.Failf("The program %s was not found\n", patuCgroupSockSend)
		}

		ginkgo.By("4. Verify cgroup_sock_addr program named patu_recvmsg4 is loaded")
		if !strings.Contains(bpfOut, patuCgroupSockRecv) {
			framework.Failf("The program %s was not found\n", patuCgroupSockRecv)
		}
	})
})

// This test validates pod to pod connectivity with a nginx deployment
/* This test does the following:
   1. Create a nginx deployment
   2. Wait for the nginx deployment to be available
   3. Create a nginx cluster ip service
   4. Create a paused deployment with a curl binary available
   5. Wait for the pause deployment to be available
   6. Retrieve the pod from the nginx deployment
   7. Retrieve the pod from the curl deployment
   8. Exec the pause pod and validate connectivity to the nginx deployment
   9. Retrieve the ClusterIP for the nginx service
   10. Exec the pause pod and validate connectivity to the nginx ClusterIP
*/
var _ = ginkgo.Describe("Validate pod to pod connectivity with a nginx deployment", func() {
	f := newPrivelegedTestFramework("pod2pod-deployment")
	curlImage := "alpine/curl:latest"
	nginxImage := "k8s.gcr.io/nginx-slim:0.8"
	curlTimeout := 5
	curlPort := "80"
	curlDeployName := "e2e-curl-deployment"
	nginxDeployName := "e2e-nginx-deployment"

	ginkgo.It("Should validate pod to pod connectivity", func() {

		ginkgo.By("1. Create a nginx deployment")
		nginxDeploySpec := e2edeployment.NewDeployment(nginxDeployName, 1,
			map[string]string{"app": "nginx"},
			"e2e-nginx",
			nginxImage,
			appsv1.RollingUpdateDeploymentStrategyType)

		nginxDeploy, err := f.ClientSet.AppsV1().Deployments(f.Namespace.Name).Create(context.TODO(), nginxDeploySpec, metav1.CreateOptions{})
		framework.ExpectNoError(err)

		ginkgo.By("2. Wait for the nginx deployment to be available")
		err = e2edeployment.WaitForDeploymentComplete(f.ClientSet, nginxDeploy)
		framework.ExpectNoError(err)

		ginkgo.By("3. Create a nginx cluster ip service")
		framework.RunKubectlOrDie(f.Namespace.Name, "create", "service", "clusterip", "nginx", "--tcp=80:80")

		ginkgo.By("4. Create a paused deployment with a curl binary available")
		curlDeploySpec := e2edeployment.NewDeployment(curlDeployName, 1,
			map[string]string{"app": "curl"},
			"e2e-curl",
			curlImage,
			appsv1.RollingUpdateDeploymentStrategyType)
		curlDeploySpec.Spec.Template.Spec.Containers[0].Args = []string{"sleep", "infinity"}

		curlDeploy, err := f.ClientSet.AppsV1().Deployments(f.Namespace.Name).Create(context.TODO(), curlDeploySpec, metav1.CreateOptions{})
		framework.ExpectNoError(err)

		ginkgo.By("5. Wait for the pause deployment to be available")
		err = e2edeployment.WaitForDeploymentComplete(f.ClientSet, curlDeploy)
		framework.ExpectNoError(err)

		ginkgo.By("6. Retrieve the pod from the nginx deployment")
		nginxPod, err := e2edeployment.GetPodsForDeployment(f.ClientSet, nginxDeploy)
		framework.ExpectNoError(err)

		ginkgo.By("7. Retrieve the pod from the curl deployment")
		curlPod, err := e2edeployment.GetPodsForDeployment(f.ClientSet, curlDeploy)
		framework.ExpectNoError(err)

		ginkgo.By("8. Exec the pause pod and validate connectivity to the nginx deployment")
		cmd := curlConnectivity(getPodAddress(nginxPod.Items[0].Name, f.Namespace.Name), curlPort, curlTimeout)
		_, _, err = f.ExecCommandInContainerWithFullOutput(curlPod.Items[0].Name, "e2e-curl", cmd...)
		if err != nil {
			framework.Failf("Failed to curl the nginx instance %s: %v", nginxPod.Items[0].Name, err)
		}

		ginkgo.By("9. Retrieve the ClusterIP for the nginx service")
		clusterIP, err := framework.RunKubectl(f.Namespace.Name, "get", "svc", "nginx", "-o", "jsonpath='{.spec.clusterIP}'")
		if err != nil {
			framework.Failf("Failed to retrieve the ClusterIP: %v", err)
		}

		ginkgo.By("10. Exec the pause pod and validate connectivity to the nginx ClusterIP")
		cmd = curlConnectivity(clusterIP, curlPort, curlTimeout)
		_, _, err = f.ExecCommandInContainerWithFullOutput(curlPod.Items[0].Name, "e2e-curl", cmd...)
		if err != nil {
			framework.Failf("Failed to curl the ClusterIP %s on the nginx instance: %v", clusterIP, err)
		}
	})
})
