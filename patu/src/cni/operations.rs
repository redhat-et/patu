// Copyright 2022 Patu
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use std::{
    env,
    net::Ipv4Addr,
    process::{Command, Stdio},
};

use log::debug;
use nix::net::if_::if_nametoindex;
use serde_json::Value;

use crate::{
    cni::types::{Error, ErrorCode, NetworkConfig, Success},
    netlink::NetlinkManager,
    Interface,
};

pub enum CniCommand {
    Add,
    Del,
    Check,
    Version,
}

#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("Command {0} is not valid")]
    InvalidCommand(String),
}

impl TryFrom<String> for CniCommand {
    type Error = ParseError;

    fn try_from(s: String) -> Result<Self, Self::Error> {
        match s.as_str() {
            "ADD" => Ok(Self::Add),
            "DEL" => Ok(Self::Del),
            "CHECK" => Ok(Self::Check),
            "VERSION" => Ok(Self::Version),
            _ => Err(ParseError::InvalidCommand(s)),
        }
    }
}

pub fn cni(config: &NetworkConfig) -> Result<Value, Error> {
    debug!("Processing CNI operation");
    let command: CniCommand = env::var("CNI_COMMAND")
        .map_err(|_| {
            Error::new(
                ErrorCode::InvalidEnvironmentVars,
                "CNI_COMMAND was not provided".to_string(),
                None,
            )
        })?
        .try_into()
        .map_err(|e: ParseError| {
            Error::new(
                ErrorCode::InvalidEnvironmentVars,
                "CNI_COMMAND is not valid".to_string(),
                Some(e.to_string()),
            )
        })?;
    let container_id = env::var("CNI_CONTAINERID").map_err(|_| {
        Error::new(
            ErrorCode::InvalidEnvironmentVars,
            "CNI_CONTAINERID was not provided".to_string(),
            None,
        )
    })?;
    let netns = env::var("CNI_NETNS").ok();
    let ifname = env::var("CNI_IFNAME").map_err(|_| {
        Error::new(
            ErrorCode::InvalidEnvironmentVars,
            "CNI_IFNAME was not provided".to_string(),
            None,
        )
    })?;
    let args = env::var("CNI_ARGS").ok();
    let path = env::var("CNI_PATH").map_err(|_| {
        Error::new(
            ErrorCode::InvalidEnvironmentVars,
            "CNI_PATH was not provided".to_string(),
            None,
        )
    })?;

    match command {
        CniCommand::Add => {
            debug!("CNI ADD");
            if netns.is_none() {
                return Err(Error::new(
                    ErrorCode::InvalidEnvironmentVars,
                    "CNI_NETNS is required but was not provided".to_string(),
                    None,
                ));
            }
            add(container_id, netns.unwrap(), ifname, args, path, config)
                .map(|s| serde_json::to_value(&s).unwrap())
        }
        CniCommand::Del => {
            debug!("CNI DEL");
            if netns.is_none() {
                return Err(Error::new(
                    ErrorCode::InvalidEnvironmentVars,
                    "CNI_NETNS is required but was not provided".to_string(),
                    None,
                ));
            }
            del(container_id, netns.unwrap(), ifname, args, path, config);
            Ok(Value::default())
        }
        CniCommand::Check => {
            if netns.is_none() {
                return Err(Error::new(
                    ErrorCode::InvalidEnvironmentVars,
                    "CNI_NETNS is required but was not provided".to_string(),
                    None,
                ));
            }
            check(container_id, netns.unwrap(), ifname, args, path)
                .map(|s| serde_json::to_value(&s).unwrap())
        }
        CniCommand::Version => version(),
    }
}

fn add(
    _container_id: String,
    netns: String,
    ifname: String,
    _args: Option<String>,
    path: String,
    config: &NetworkConfig,
) -> Result<Success, Error> {
    debug!("Calling IPAM Plugin");
    let mut result = match call_ipam(config, path.clone(), true) {
        Ok(r) => Ok(r),
        Err(e) => {
            env::set_var("CNI_COMMAND", "DEL");
            let _ = call_ipam(config, path, false);
            Err(e)
        }
    }?;
    debug!("Creating Netlink Sockets");
    let hostns = NetlinkManager::new();
    let containerns = NetlinkManager::new_in_namespace(netns.clone()).map_err(|e| {
        Error::new_custom(
            102,
            "Error creating netlink socket in container ns".to_string(),
            Some(e.to_string()),
        )
    })?;
    debug!("Creating Gateway Interface");
    if let Some(iface) = hostns.create_gateway().map_err(|e| {
        Error::new_custom(
            102,
            "Error creating gateway".to_string(),
            Some(e.to_string()),
        )
    })? {
        if let Some(ifaces) = result.interfaces.as_mut() {
            ifaces.push(Interface {
                name: iface.name,
                mac: iface.mac,
                sandbox: None,
            });
        } else {
            result.interfaces = Some(vec![Interface {
                name: iface.name,
                mac: iface.mac,
                sandbox: None,
            }])
        }
    };
    let gw_index = if_nametoindex("patu0")
        .map_err(|_| Error::new_custom(102, "Error getting gateway".to_string(), None))?;
    let gw_addr: Ipv4Addr = result.ips[0].gateway.parse().unwrap();
    hostns.set_ip(gw_index, gw_addr).map_err(|e| {
        Error::new_custom(
            102,
            "Error setting gateway IP".to_string(),
            Some(e.to_string()),
        )
    })?;
    debug!("Creating Container Interface");
    let (host, veth) = hostns
        .create_veth_pair(ifname, netns.clone(), 1500)
        .map_err(|e| {
            Error::new_custom(
                102,
                "Error creating container interfaces".to_string(),
                Some(e.to_string()),
            )
        })?;

    debug!("attempting to set veth up via host side");
    hostns.set_up(host.ifindex).map_err(|e| {
        Error::new_custom(
            102,
            "Error setting veth interface to up".to_string(),
            Some(e.to_string()),
        )
    })?;

    debug!("getting veth link info");
    let (veth_ifindex, veth_mac) = containerns.get_link_info(veth.name.clone()).map_err(|e| {
        Error::new_custom(
            102,
            "Error getting veth info".to_string(),
            Some(e.to_string()),
        )
    })?;

    debug!("setting veth ip address");
    let veth_addr: Ipv4Addr = ip4_addr_from_cidr(result.ips[0].address.clone());
    containerns.set_ip(veth_ifindex, veth_addr).map_err(|e| {
        Error::new_custom(
            102,
            "Error setting veth IP".to_string(),
            Some(e.to_string()),
        )
    })?;
    debug!("attempting to set veth up via veth side");
    containerns.set_up(veth_ifindex).map_err(|e| {
        Error::new_custom(
            102,
            "Error setting veth interface to up".to_string(),
            Some(e.to_string()),
        )
    })?;

    debug!("attempting to add route to host side of interface");
    containerns
        .create_dev_route(veth_ifindex, gw_addr)
        .map_err(|e| {
            Error::new_custom(
                102,
                "Error creating route to host-side IP".to_string(),
                Some(e.to_string()),
            )
        })?;
    debug!("attempting to add default route");
    containerns.create_default_route(gw_addr).map_err(|e| {
        Error::new_custom(
            102,
            "Error creating container default route".to_string(),
            Some(e.to_string()),
        )
    })?;

    let ipt = iptables::new(false).unwrap();
    ipt.append(
        "filter",
        "FORWARD",
        format!("-i {} -j ACCEPT", host.name).as_str(),
    )
    .map_err(|e| {
        Error::new_custom(
            102,
            "Can't set up forwarding rules".to_string(),
            Some(e.to_string()),
        )
    })?;

    hostns
        .create_dev_route(host.ifindex, veth_addr)
        .map_err(|e| {
            Error::new_custom(
                102,
                "Error creating route to container IP".to_string(),
                Some(e.to_string()),
            )
        })?;

    if let Some(ifaces) = result.interfaces.as_mut() {
        ifaces.push(Interface {
            name: host.name,
            mac: host.mac,
            sandbox: None,
        });
        ifaces.push(Interface {
            name: veth.name,
            mac: Some(veth_mac),
            sandbox: Some(netns),
        });
    } else {
        result.interfaces = Some(vec![
            Interface {
                name: host.name,
                mac: host.mac,
                sandbox: None,
            },
            Interface {
                name: veth.name,
                mac: Some(veth_mac),
                sandbox: Some(netns),
            },
        ])
    }
    Ok(result)
}

fn del(
    _container_id: String,
    netns: String,
    ifname: String,
    _args: Option<String>,
    path: String,
    config: &NetworkConfig,
) {
    debug!("Creating Netlink Sockets");
    let containerns = match NetlinkManager::new_in_namespace(netns) {
        Ok(r) => r,
        Err(_) => return,
    };

    let ifindex = match containerns.get_link_info(ifname) {
        Ok((i, _)) => i,
        Err(_) => return,
    };

    // This will remove eveyrthing that references this interface
    // That includes routes and iptables rules
    let _ = containerns.delete_link(ifindex);

    debug!("Calling IPAM Plugin");
    let _ = call_ipam(config, path, false);
}

fn check(
    _container_id: String,
    _netns: String,
    _ifname: String,
    _args: Option<String>,
    _path: String,
) -> Result<Success, Error> {
    Ok(Success::default())
}

fn version() -> Result<Value, Error> {
    Ok(serde_json::json!(
        {
            "cniVersion": "1.0.0",
            "supportedVersions": [ "1.0.0" ]
        }
    ))
}

fn call_ipam(
    config: &NetworkConfig,
    cni_path: String,
    parse_result: bool,
) -> Result<Success, Error> {
    if let Some(ipam) = &config.plugin.ipam {
        // Process will inherit the same ENV variables as we received.
        // No need to filter or clear them
        debug!("Executing {}", ipam.type_.to_string());
        let mut cmd = Command::new(&ipam.type_)
            // Binary should reside on cni_path
            .env("PATH", cni_path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| Error::new_custom(101, "IPAM Error".to_string(), Some(e.to_string())))?;

        debug!(
            "Sending config to process stdin:\n{}",
            serde_json::to_string(&config).unwrap()
        );
        let stdin = cmd.stdin.as_mut().ok_or_else(|| {
            Error::new_custom(101, "unable to get ipam process stdin".to_string(), None)
        })?;
        serde_json::to_writer(stdin, config)
            .map_err(|e| Error::new_custom(101, "IPAM Error".to_string(), Some(e.to_string())))?;

        debug!("Awaiting process output");
        let output = cmd
            .wait_with_output()
            .map_err(|e| Error::new_custom(101, "IPAM Error".to_string(), Some(e.to_string())))?;

        debug!("Process Completed");
        debug!(
            "STDOUT:\n{}\nSTDERR:\n{}\n",
            std::str::from_utf8(&output.stdout).unwrap(),
            std::str::from_utf8(&output.stderr).unwrap(),
        );
        if output.status.success() {
            debug!("Command completed succesfully");
            let success: Success = if parse_result {
                serde_json::from_slice(&output.stdout).map_err(|e| {
                    Error::new_custom(101, "IPAM Error".to_string(), Some(e.to_string()))
                })?
            } else {
                Success::default()
            };
            Ok(success)
        } else {
            debug!("Command completed unsuccesfully");
            // TODO: Should we also check stderr just in case?
            let error: Error = if parse_result {
                serde_json::from_slice(&output.stdout).map_err(|e| {
                    Error::new_custom(101, "IPAM Error".to_string(), Some(e.to_string()))
                })?
            } else {
                Error::new_custom(101, "IPAM Error".to_string(), None)
            };
            Err(error)
        }
    } else {
        debug!("No IPAM configuration");
        Ok(Success::default())
    }
}

fn ip4_addr_from_cidr(cidr: String) -> Ipv4Addr {
    if let Some(pos) = cidr.rfind('/') {
        cidr[0..pos].parse().unwrap()
    } else {
        cidr.parse().unwrap()
    }
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_ip4_addr_from_cidr() {
        let a1 = ip4_addr_from_cidr("10.10.1.1/24".to_string());
        assert_eq!(a1, Ipv4Addr::new(10, 10, 1, 1));
    }
}
