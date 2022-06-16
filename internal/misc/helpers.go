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
package misc

import (
	"fmt"

	"github.com/containernetworking/cni/pkg/skel"
)

func PrintCmdArgs (args *skel.CmdArgs ) {
	fmt.Printf("CMD_ADD: %s - %s - %s - %s - %s - %s", 
	args.ContainerID, 
	args.IfName, 
	args.Netns, 
	args.Path, 
	args.Args, 
	string(args.StdinData))
}