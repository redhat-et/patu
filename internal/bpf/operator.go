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
package bpf

import (
	"cmd/patu/app/configs"
	"fmt"
)

func CompileEbpfProg() error {
	if err := compileEbpfProg(configs.Debug); err != nil {
		return fmt.Errorf("eBPF program compilation failed with : %v", err)
	}
	return nil
}

func LoadAndAttachBPFProg() error {
	var err error
	if err = loadBpfProg(configs.Debug); err != nil {
		return fmt.Errorf("eBPF program loading failed with : %v", err)
	}

	if err = attachBpfProg(); err != nil {
		return fmt.Errorf("eBPF program attach failed with : %v", err)
	}
	return nil
}

func UnloadBpfProg() error {
	if err := unloadBpfProg(); err != nil {
		return fmt.Errorf("eBPF program unloading failed with :  %v", err)
	}
	return nil
}