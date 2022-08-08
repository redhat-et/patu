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
	"fmt"
	"os/exec"
	"strings"

	"github.com/onsi/ginkgo"
	"k8s.io/kubernetes/test/e2e/framework"
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
	ginkgo.It("1. Verify sock_ops named patu_sockops program is loaded", func() {
		if !strings.Contains(bpfOut, patuSockOps) {
			framework.Failf("The program %s was not found\n", patuSockOps)
		}
	})
	ginkgo.It("2. Verify sk_msg program named patu_skmsg is loaded", func() {
		if !strings.Contains(bpfOut, patuSkMsg) {
			framework.Failf("The program %s was not found\n", patuSkMsg)
		}
	})
	ginkgo.It("3. Verify cgroup_sock_addr program named patu_sendmsg4 is loaded", func() {
		if !strings.Contains(bpfOut, patuCgroupSockSend) {
			framework.Failf("The program %s was not found\n", patuCgroupSockSend)
		}
	})
	ginkgo.It("4. Verify cgroup_sock_addr program named patu_recvmsg4 is loaded", func() {
		if !strings.Contains(bpfOut, patuCgroupSockRecv) {
			framework.Failf("The program %s was not found\n", patuCgroupSockRecv)
		}
	})
})
