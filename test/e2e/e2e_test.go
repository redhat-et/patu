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
	"flag"
	"fmt"
	"os"
	"path"
	"testing"

	"github.com/onsi/ginkgo"
	"github.com/onsi/ginkgo/config"
	"github.com/onsi/ginkgo/reporters"
	"github.com/onsi/gomega"
	"k8s.io/klog/v2"
	"k8s.io/kubernetes/test/e2e/framework"
	e2econfig "k8s.io/kubernetes/test/e2e/framework/config"
	"k8s.io/kubernetes/test/e2e/framework/testfiles"
	"k8s.io/kubernetes/test/utils/image"
)

// handleFlags sets up all flags and parses the command line.
func handleFlags() {
	e2econfig.CopyFlags(e2econfig.Flags, flag.CommandLine)
	framework.RegisterCommonFlags(flag.CommandLine)
	framework.RegisterClusterFlags(flag.CommandLine)
	flag.Parse()
}

// required due to go1.13
func TestMain(m *testing.M) {
	// Register test flags, then parse flags.
	handleFlags()

	if framework.TestContext.ListImages {
		for _, v := range image.GetImageConfigs() {
			fmt.Println(v.GetE2EImage())
		}
		os.Exit(0)
	}

	framework.AfterReadingAllFlags(&framework.TestContext)

	if framework.TestContext.RepoRoot != "" {
		testfiles.AddFileSource(testfiles.RootFileSource{Root: framework.TestContext.RepoRoot})
	}

	os.Exit(m.Run())
}

func TestE2e(t *testing.T) {
	// Run tests through the Ginkgo runner with output to console + JUnit for reporting
	var r []ginkgo.Reporter
	if framework.TestContext.ReportDir != "" {
		klog.Infof("Saving reports to %s", framework.TestContext.ReportDir)
		if err := os.MkdirAll(framework.TestContext.ReportDir, 0755); err != nil {
			klog.Errorf("Failed creating report directory: %v", err)
		} else {
			r = append(r, reporters.NewJUnitReporter(path.Join(framework.TestContext.ReportDir, fmt.Sprintf("junit_%v%02d.xml", framework.TestContext.ReportPrefix, config.GinkgoConfig.ParallelNode))))
		}
	}

	gomega.RegisterFailHandler(framework.Fail)
	ginkgo.RunSpecsWithDefaultAndCustomReporters(t, "Patu E2e Suite", r)
}
