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

package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/vishvananda/netlink"

	"github.com/containernetworking/cni/pkg/skel"
	"github.com/containernetworking/cni/pkg/types"
	current "github.com/containernetworking/cni/pkg/types/100"
	"github.com/containernetworking/cni/pkg/version"
	"github.com/containernetworking/plugins/pkg/ip"
	"github.com/containernetworking/plugins/pkg/ipam"
	"github.com/containernetworking/plugins/pkg/ns"
	"github.com/containernetworking/plugins/pkg/utils/sysctl"
)

type PodWatcher struct {

}

const defaultBrName = "cni0"

type NetConf struct {
	types.NetConf
	BrName       string `json:"defaultBridge"`
	MTU          int    `json:"mtu"`
	EnableDad    bool   `json:"enabledad,omitempty"`
	mac string
}

type BridgeArgs struct {
	Mac string `json:"mac,omitempty"`
}

// MacEnvArgs represents CNI_ARGS
type MacEnvArgs struct {
	types.CommonArgs
	MAC types.UnmarshallableString `json:"mac,omitempty"`
}

func NewPodWatcher() (*PodWatcher) {
	return &PodWatcher{}
}

func loadNetConf(bytes []byte, envArgs string) (*NetConf, string, error) {
	n := &NetConf{
		BrName: defaultBrName,
	}
	if err := json.Unmarshal(bytes, n); err != nil {
		return nil, "", fmt.Errorf("failed to load netconf: %v", err)
	}

	if envArgs != "" {
		e := MacEnvArgs{}
		if err := types.LoadArgs(envArgs, &e); err != nil {
			return nil, "", err
		}

		if e.MAC != "" {
			n.mac = string(e.MAC)
		}
	}
	return n, n.CNIVersion, nil
}

func bridgeByName(name string) (*netlink.Bridge, error) {
	l, err := netlink.LinkByName(name)
	if err != nil {
		return nil, fmt.Errorf("could not lookup %q: %v", name, err)
	}
	br, ok := l.(*netlink.Bridge)
	if !ok {
		return nil, fmt.Errorf("%q already exists but is not a bridge", name)
	}
	return br, nil
}

func setupVeth(netns ns.NetNS, br *netlink.Bridge, ifName string, mtu int, mac string) (*current.Interface, *current.Interface, error) {
	contIface := &current.Interface{}
	hostIface := &current.Interface{}

	err := netns.Do(func(hostNS ns.NetNS) error {
		// create the veth pair in the container and move host end into host netns
		hostVeth, containerVeth, err := ip.SetupVeth(ifName, mtu, mac, hostNS)
		if err != nil {
			return err
		}
		contIface.Name = containerVeth.Name
		contIface.Mac = containerVeth.HardwareAddr.String()
		contIface.Sandbox = netns.Path()
		hostIface.Name = hostVeth.Name
		return nil
	})
	if err != nil {
		return nil, nil, err
	}

	// need to lookup hostVeth again as its index has changed during ns move
	hostVeth, err := netlink.LinkByName(hostIface.Name)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to lookup %q: %v", hostIface.Name, err)
	}
	hostIface.Mac = hostVeth.Attrs().HardwareAddr.String()

	// connect host veth end to the bridge
	if err := netlink.LinkSetMaster(hostVeth, br); err != nil {
		return nil, nil, fmt.Errorf("failed to connect %q to bridge %v: %v", hostVeth.Attrs().Name, br.Attrs().Name, err)
	}

	return hostIface, contIface, nil
}

func getDefaultBridge(n *NetConf) (*netlink.Bridge, *current.Interface, error) {
	
	br, err := bridgeByName(n.BrName)
	if err != nil {
		return nil, nil, err
	}

	// we want to own the routes for this interface
	_, _ = sysctl.Sysctl(fmt.Sprintf("net/ipv6/conf/%s/accept_ra", n.BrName), "0")

	return br, &current.Interface{
		Name: br.Attrs().Name,
		Mac:  br.Attrs().HardwareAddr.String(),
	}, nil
}

func (pw *PodWatcher) cmdAdd(args *skel.CmdArgs) error {
	var success bool = false

	n, cniVersion, err := loadNetConf(args.StdinData, args.Args)
	if err != nil {
		return err
	}

	isLayer3 := n.IPAM.Type != ""

	br, brInterface, err := getDefaultBridge(n)
	if err != nil {
		return err
	}

	netns, err := ns.GetNS(args.Netns)
	if err != nil {
		return fmt.Errorf("failed to open netns %q: %v", args.Netns, err)
	}
	defer netns.Close()

	hostInterface, containerInterface, err := setupVeth(netns, br, args.IfName, n.MTU, n.mac)
	if err != nil {
		return err
	}

	// Assume L2 interface only
	result := &current.Result{
		CNIVersion: current.ImplementedSpecVersion,
		Interfaces: []*current.Interface{
			brInterface,
			hostInterface,
			containerInterface,
		},
	}

	if isLayer3 {
		// run the IPAM plugin and get back the config to apply
		r, err := ipam.ExecAdd(n.IPAM.Type, args.StdinData)
		if err != nil {
			return err
		}

		// release IP in case of failure
		defer func() {
			if !success {
				if err := ipam.ExecDel(n.IPAM.Type, args.StdinData); err != nil {
					fmt.Fprintf(os.Stderr, "%v", err)
				}
			}
		}()

		// Convert whatever the IPAM result was into the current Result type
		ipamResult, err := current.NewResultFromResult(r)
		if err != nil {
			return err
		}

		result.IPs = ipamResult.IPs
		result.Routes = ipamResult.Routes
		result.DNS = ipamResult.DNS

		if len(result.IPs) == 0 {
			return errors.New("IPAM plugin returned missing IP config")
		}

		// Configure the container hardware address and IP address(es)
		if err := netns.Do(func(_ ns.NetNS) error {
			if n.EnableDad {
				_, _ = sysctl.Sysctl(fmt.Sprintf("/net/ipv6/conf/%s/enhanced_dad", args.IfName), "1")
				_, _ = sysctl.Sysctl(fmt.Sprintf("net/ipv6/conf/%s/accept_dad", args.IfName), "1")
			} else {
				_, _ = sysctl.Sysctl(fmt.Sprintf("net/ipv6/conf/%s/accept_dad", args.IfName), "0")
			}
			_, _ = sysctl.Sysctl(fmt.Sprintf("net/ipv4/conf/%s/arp_notify", args.IfName), "1")

			// Add the IP to the interface
			if err := ipam.ConfigureIface(args.IfName, result); err != nil {
				return err
			}
			return nil
		}); err != nil {
			return err
		}

		// check bridge port state
		retries := []int{0, 50, 500, 1000, 1000}
		for idx, sleep := range retries {
			time.Sleep(time.Duration(sleep) * time.Millisecond)

			hostVeth, err := netlink.LinkByName(hostInterface.Name)
			if err != nil {
				return err
			}
			if hostVeth.Attrs().OperState == netlink.OperUp {
				break
			}

			if idx == len(retries)-1 {
				return fmt.Errorf("bridge port in error state: %s", hostVeth.Attrs().OperState)
			}
		}
	} else {
		if err := netns.Do(func(_ ns.NetNS) error {
			link, err := netlink.LinkByName(args.IfName)
			if err != nil {
				return fmt.Errorf("failed to retrieve link: %v", err)
			}
			// If layer 2 we still need to set the container veth to up
			if err = netlink.LinkSetUp(link); err != nil {
				return fmt.Errorf("failed to set %q up: %v", args.IfName, err)
			}
			return nil
		}); err != nil {
			return err
		}
	}

	// Refetch the bridge since its MAC address may change when the first
	// veth is added or after its IP address is set
	br, err = bridgeByName(n.BrName)
	if err != nil {
		return err
	}
	brInterface.Mac = br.Attrs().HardwareAddr.String()

	success = true

	return types.PrintResult(result, cniVersion)
}

func (pw *PodWatcher) cmdDel(args *skel.CmdArgs) error {
	n, _, err := loadNetConf(args.StdinData, args.Args)
	if err != nil {
		return err
	}

	isLayer3 := n.IPAM.Type != ""

	ipamDel := func() error {
		if isLayer3 {
			if err := ipam.ExecDel(n.IPAM.Type, args.StdinData); err != nil {
				return err
			}
		}
		return nil
	}

	if args.Netns == "" {
		return ipamDel()
	}

	// There is a netns so try to clean up. Delete can be called multiple times
	// so don't return an error if the device is already removed.
	// If the device isn't there then don't try to clean up IP masq either.
	err = ns.WithNetNSPath(args.Netns, func(_ ns.NetNS) error {
		var err error
		_, err = ip.DelLinkByNameAddr(args.IfName)
		if err != nil && err == ip.ErrLinkNotFound {
			return nil
		}
		return err
	})

	if err != nil {
		//  if NetNs is passed down by the Cloud Orchestration Engine, or if it called multiple times
		// so don't return an error if the device is already removed.
		// https://github.com/kubernetes/kubernetes/issues/43014#issuecomment-287164444
		_, ok := err.(ns.NSPathNotExistErr)
		if ok {
			return ipamDel()
		}
		return err
	}

	// call ipam.ExecDel after clean up device in netns
	if err := ipamDel(); err != nil {
		return err
	}

	return err
}

type cniBridgeIf struct {
	Name        string
	ifIndex     int
	peerIndex   int
	masterIndex int
	found       bool
}

func validateInterface(intf current.Interface, expectInSb bool) (cniBridgeIf, netlink.Link, error) {

	ifFound := cniBridgeIf{found: false}
	if intf.Name == "" {
		return ifFound, nil, fmt.Errorf("Interface name missing ")
	}

	link, err := netlink.LinkByName(intf.Name)
	if err != nil {
		return ifFound, nil, fmt.Errorf("Interface name %s not found", intf.Name)
	}

	if expectInSb {
		if intf.Sandbox == "" {
			return ifFound, nil, fmt.Errorf("Interface %s is expected to be in a sandbox", intf.Name)
		}
	} else {
		if intf.Sandbox != "" {
			return ifFound, nil, fmt.Errorf("Interface %s should not be in sandbox", intf.Name)
		}
	}

	return ifFound, link, err
}

func validateCniBrInterface(intf current.Interface, n *NetConf) (cniBridgeIf, error) {

	brFound, link, err := validateInterface(intf, false)
	if err != nil {
		return brFound, err
	}

	_, isBridge := link.(*netlink.Bridge)
	if !isBridge {
		return brFound, fmt.Errorf("Interface %s does not have link type of bridge", intf.Name)
	}

	if intf.Mac != "" {
		if intf.Mac != link.Attrs().HardwareAddr.String() {
			return brFound, fmt.Errorf("Bridge interface %s Mac doesn't match: %s", intf.Name, intf.Mac)
		}
	}

	brFound.found = true
	brFound.Name = link.Attrs().Name
	brFound.ifIndex = link.Attrs().Index
	brFound.masterIndex = link.Attrs().MasterIndex

	return brFound, nil
}

func validateCniVethInterface(intf *current.Interface, brIf cniBridgeIf, contIf cniBridgeIf) (cniBridgeIf, error) {

	vethFound, link, err := validateInterface(*intf, false)
	if err != nil {
		return vethFound, err
	}

	_, isVeth := link.(*netlink.Veth)
	if !isVeth {
		// just skip it, it's not what CNI created
		return vethFound, nil
	}

	_, vethFound.peerIndex, err = ip.GetVethPeerIfindex(link.Attrs().Name)
	if err != nil {
		return vethFound, fmt.Errorf("Unable to obtain veth peer index for veth %s", link.Attrs().Name)
	}
	vethFound.ifIndex = link.Attrs().Index
	vethFound.masterIndex = link.Attrs().MasterIndex

	if vethFound.ifIndex != contIf.peerIndex {
		return vethFound, nil
	}

	if contIf.ifIndex != vethFound.peerIndex {
		return vethFound, nil
	}

	if vethFound.masterIndex != brIf.ifIndex {
		return vethFound, nil
	}

	if intf.Mac != "" {
		if intf.Mac != link.Attrs().HardwareAddr.String() {
			return vethFound, fmt.Errorf("Interface %s Mac doesn't match: %s not found", intf.Name, intf.Mac)
		}
	}

	vethFound.found = true
	vethFound.Name = link.Attrs().Name

	return vethFound, nil
}

func validateCniContainerInterface(intf current.Interface) (cniBridgeIf, error) {

	vethFound, link, err := validateInterface(intf, true)
	if err != nil {
		return vethFound, err
	}

	_, isVeth := link.(*netlink.Veth)
	if !isVeth {
		return vethFound, fmt.Errorf("Error: Container interface %s not of type veth", link.Attrs().Name)
	}
	_, vethFound.peerIndex, err = ip.GetVethPeerIfindex(link.Attrs().Name)
	if err != nil {
		return vethFound, fmt.Errorf("Unable to obtain veth peer index for veth %s", link.Attrs().Name)
	}
	vethFound.ifIndex = link.Attrs().Index

	if intf.Mac != "" {
		if intf.Mac != link.Attrs().HardwareAddr.String() {
			return vethFound, fmt.Errorf("Interface %s Mac %s doesn't match container Mac: %s", intf.Name, intf.Mac, link.Attrs().HardwareAddr)
		}
	}

	vethFound.found = true
	vethFound.Name = link.Attrs().Name

	return vethFound, nil
}

func (pw *PodWatcher) cmdCheck(args *skel.CmdArgs) error {

	n, _, err := loadNetConf(args.StdinData, args.Args)
	if err != nil {
		return err
	}
	netns, err := ns.GetNS(args.Netns)
	if err != nil {
		return fmt.Errorf("failed to open netns %q: %v", args.Netns, err)
	}
	defer netns.Close()

	// run the IPAM plugin and get back the config to apply
	err = ipam.ExecCheck(n.IPAM.Type, args.StdinData)
	if err != nil {
		return err
	}

	// Parse previous result.
	if n.NetConf.RawPrevResult == nil {
		return fmt.Errorf("Required prevResult missing")
	}

	if err := version.ParsePrevResult(&n.NetConf); err != nil {
		return err
	}

	result, err := current.NewResultFromResult(n.PrevResult)
	if err != nil {
		return err
	}

	var errLink error
	var contCNI, vethCNI cniBridgeIf
	var brMap, contMap current.Interface

	// Find interfaces for names we know, CNI Bridge and container
	for _, intf := range result.Interfaces {
		if n.BrName == intf.Name {
			brMap = *intf
			continue
		} else if args.IfName == intf.Name {
			if args.Netns == intf.Sandbox {
				contMap = *intf
				continue
			}
		}
	}

	brCNI, err := validateCniBrInterface(brMap, n)
	if err != nil {
		return err
	}

	// The namespace must be the same as what was configured
	if args.Netns != contMap.Sandbox {
		return fmt.Errorf("Sandbox in prevResult %s doesn't match configured netns: %s",
			contMap.Sandbox, args.Netns)
	}

	// Check interface against values found in the container
	if err := netns.Do(func(_ ns.NetNS) error {
		contCNI, errLink = validateCniContainerInterface(contMap)
		if errLink != nil {
			return errLink
		}
		return nil
	}); err != nil {
		return err
	}

	// Now look for veth that is peer with container interface.
	// Anything else wasn't created by CNI, skip it
	for _, intf := range result.Interfaces {
		// Skip this result if name is the same as cni bridge
		// It's either the cni bridge we dealt with above, or something with the
		// same name in a different namespace.  We just skip since it's not ours
		if brMap.Name == intf.Name {
			continue
		}

		// same here for container name
		if contMap.Name == intf.Name {
			continue
		}

		vethCNI, errLink = validateCniVethInterface(intf, brCNI, contCNI)
		if errLink != nil {
			return errLink
		}

		if vethCNI.found {
			// veth with container interface as peer and bridge as master found
			break
		}
	}

	if !brCNI.found {
		return fmt.Errorf("CNI created bridge %s in host namespace was not found", n.BrName)
	}
	if !contCNI.found {
		return fmt.Errorf("CNI created interface in container %s not found", args.IfName)
	}
	if !vethCNI.found {
		return fmt.Errorf("CNI veth created for bridge %s was not found", n.BrName)
	}

	// Check prevResults for ips, routes and dns against values found in the container
	if err := netns.Do(func(_ ns.NetNS) error {
		err = ip.ValidateExpectedInterfaceIPs(args.IfName, result.IPs)
		if err != nil {
			return err
		}

		return nil
	}); err != nil {
		return err
	}

	return nil
}
