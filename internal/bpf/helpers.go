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
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/cilium/ebpf"
	"github.com/redhat-et/patu/configs"
)

const (
	progPath = "./bpf"
)

func compileEbpfProg(debug bool) error {
	cmd := exec.Command("make", "compile")
	cmd.Dir = progPath
	cmd.Env = os.Environ()

	if debug {
		cmd.Env = append(cmd.Env, "DEBUG=1")
	}

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	if code := cmd.ProcessState.ExitCode(); code != 0 || err != nil {
		return fmt.Errorf("\"%s \" failed with code: %d, err: %v", strings.Join(cmd.Args, " "), code, err)
	}
	fmt.Println("eBPF programs compiled successfully.")
	return nil
}

func loadBpfMaps(debug bool) error {
	if os.Getuid() != 0 {
		return fmt.Errorf("eBPF map loading requires root privileges.")
	}
	cmd := exec.Command("make", "load-maps")
	cmd.Dir = progPath
	cmd.Env = os.Environ()

	if debug {
		cmd.Env = append(cmd.Env, "DEBUG=1")
	}

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	if code := cmd.ProcessState.ExitCode(); code != 0 || err != nil {
		return fmt.Errorf("\"%s \" failed with code: %d, err: %v", strings.Join(cmd.Args, " "), code, err)
	}
	fmt.Println("eBPF maps loaded successfully.")
	return nil
}

func loadBpfProg(debug bool) error {
	if os.Getuid() != 0 {
		return fmt.Errorf("eBPF program loading requires root privileges.")
	}
	cmd := exec.Command("make", "load-prog")
	cmd.Dir = progPath
	cmd.Env = os.Environ()

	if debug {
		cmd.Env = append(cmd.Env, "DEBUG=1")
	}

	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	if code := cmd.ProcessState.ExitCode(); code != 0 || err != nil {
		return fmt.Errorf("\"%s \" failed with code: %d, err: %v", strings.Join(cmd.Args, " "), code, err)
	}
	fmt.Println("eBPF programs loaded successfully.")
	return nil
}

func attachBpfProg() error {
	if os.Getuid() != 0 {
		return fmt.Errorf("eBPF program loading requires root privileges.")
	}
	cmd := exec.Command("make", "attach-prog")
	cmd.Dir = progPath
	cmd.Env = os.Environ()
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if code := cmd.ProcessState.ExitCode(); code != 0 || err != nil {
		return fmt.Errorf("\"%s \" failed with code: %d, err: %v", strings.Join(cmd.Args, " "), code, err)
	}
	fmt.Println("eBPF programs attached successfully.")
	return nil
}

func detachBpfProg() error {
	cmd := exec.Command("make", "detach-prog")
	cmd.Dir = progPath
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if code := cmd.ProcessState.ExitCode(); code != 0 || err != nil {
		return fmt.Errorf("\"%s \" failed with code: %d, err: %v", strings.Join(cmd.Args, " "), code, err)
	}
	fmt.Println("eBPF programs detached successfully.")
	return nil
}

func unloadBpfProg() error {
	cmd := exec.Command("make", "unload-prog")
	cmd.Dir = progPath
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if code := cmd.ProcessState.ExitCode(); code != 0 || err != nil {
		return fmt.Errorf("\"%s \" failed with code: %d, err: %v", strings.Join(cmd.Args, " "), code, err)
	}
	fmt.Println("eBPF programs unloaded successfully.")
	return nil
}

func unloadBpfMaps() error {
	cmd := exec.Command("make", "unload-maps")
	cmd.Dir = progPath
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if code := cmd.ProcessState.ExitCode(); code != 0 || err != nil {
		return fmt.Errorf("\"%s \" failed with code: %d, err: %v", strings.Join(cmd.Args, " "), code, err)
	}
	fmt.Println("eBPF maps unloaded successfully.")
	return nil
}

func getPinnedMap(mapMountPath string) (*ebpf.Map, error) {
	configMap, err := ebpf.LoadPinnedMap(configs.ConfigMapFsMount, &ebpf.LoadPinOptions{})
	if err != nil {
		return nil, fmt.Errorf("Error loading config map %s : %v", configs.ConfigMapFsMount, err)
	}
	return configMap, nil
}

func updateConfigMap(mapMountPath string, mapKey uint32, mapValue []byte) error {
	
	if configMap, _:= getPinnedMap(mapMountPath); configMap == nil {
		return fmt.Errorf("Failed to get pinned config map %s", mapMountPath)

	} else {
		if err := configMap.Update(mapKey, mapValue, ebpf.UpdateAny); err != nil {
			return fmt.Errorf("Failed to updated config map with key %d, value %x. Error = %v", mapKey, mapValue, err)
		}
	}
	return nil
}
