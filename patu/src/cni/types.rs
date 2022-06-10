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

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// The configuration format used by administrators to express their CNI configuration
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Config {
    /// CNI Spec Version
    #[serde(rename = "cniVersion")]
    pub cni_version: String,
    /// Network name
    pub name: String,
    /// Disable check
    #[serde(skip_serializing_if = "Option::is_none")]
    pub disable_check: Option<bool>,
    /// Plugin Configuration
    pub plugins: Vec<PluginConfig>,
}

/// The configration object supplied on STDIN to a CNI plugin
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct NetworkConfig {
    /// CNI Spec Version
    #[serde(rename = "cniVersion")]
    pub cni_version: String,
    /// Network name
    pub name: String,
    /// Disable check
    #[serde(skip_serializing_if = "Option::is_none")]
    pub disable_check: Option<bool>,
    /// Plugin Configuration
    #[serde(flatten)]
    pub plugin: PluginConfig,
}

/// Plugin configuration options
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PluginConfig {
    /// Matches the name of the CNI plugin on disk
    #[serde(rename = "type")]
    pub type_: String,
    /// Plugin capabilities
    #[serde(skip_serializing_if = "Option::is_none")]
    pub capabilities: Option<HashMap<String, Value>>,
    /// If supported by the plugin, sets up an IP masquerade on the host for this network.
    /// This is necessary if the host will act as a gateway to subnets that are not able to route to the IP assigned to the container.
    #[serde(rename = "ipMasq")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ip_masquerade: Option<bool>,

    /// IPAM configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ipam: Option<Ipam>,

    /// DNS Configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dns: Option<Dns>,

    /// The result of the previous operation
    #[serde(rename = "prevResult")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prev_result: Option<Success>,

    /// Additional plugin configuration is flattened
    #[serde(flatten)]
    pub extra: HashMap<String, Value>,
}

/// IP Address Management Configuration
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Ipam {
    #[serde(rename = "type")]
    pub type_: String,

    #[serde(flatten)]
    pub other: HashMap<String, Value>,
}

/// The message sent on a successful operation
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Success {
    /// CNI specification version
    #[serde(rename = "cniVersion")]
    pub cni_version: String,
    /// An array of all interfaces created by the attachment, including any host-level interfaces
    /// May be None for a Delegated IPAM Plugin
    #[serde(skip_serializing_if = "Option::is_none")]
    pub interfaces: Option<Vec<Interface>>,
    /// IPs assigned by this attachment. Plugins may include IPs assigned external to the container.
    pub ips: Vec<Ip>,
    /// Routes created by this attachment:
    pub routes: Vec<Route>,
    ///  DNS configuration information
    pub dns: Dns,
}

/// A representation of an Interface that was added by a CNI plugin
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Interface {
    /// The name of the interface.
    pub name: String,
    /// The hardware address of the interface (if applicable).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mac: Option<String>,
    /// The isolation domain reference (e.g. path to network namespace) for the interface, or empty if on the host.
    /// For interfaces created inside the container, this should be the value passed via CNI_NETNS.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox: Option<String>,
}

/// An IP Address assignment that was added by a CNI Plugin
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Ip {
    /// An IP address in CIDR notation (eg "192.168.1.3/24").
    pub address: String,
    /// The default gateway for this subnet, if one exists.
    pub gateway: String,
    /// The index into the interfaces list for a CNI Plugin Result indicating which interface this IP configuration should be applied to.
    /// May be None for a Delegated IPAM Plugin
    #[serde(skip_serializing_if = "Option::is_none")]
    pub interface: Option<u64>,
}

/// A Route that was added by a CNI Plugin
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Route {
    /// The destination of the route, in CIDR notation
    pub dst: String,
    /// The next hop address. If unset, a value in gateway in the ips array may be used.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gw: Option<String>,
}

/// DNS Server Configuration
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Dns {
    /// List of a priority-ordered list of DNS nameservers that this network is aware of.
    /// Each entry in the list is a string containing either an IPv4 or an IPv6 address.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nameservers: Option<Vec<String>>,
    /// The local domain used for short hostname lookups.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub domain: Option<String>,
    /// List of priority ordered search domains for short hostname lookups. Will be preferred over domain by most resolvers.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub search: Option<Vec<String>>,
    /// List of options that can be passed to the resolver.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<String>>,
}

/// The Error Message sent when a operation has failed
#[derive(Default, Debug, Clone, Serialize, Deserialize)]
pub struct Error {
    /// A numeric error code
    pub code: u64,
    /// A short message characterizing the error
    pub msg: String,
    /// A longer message describing the error
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
}

impl Error {
    pub fn new(code: ErrorCode, msg: String, details: Option<String>) -> Self {
        Error {
            code: code as u64,
            msg,
            details,
        }
    }
    pub fn new_custom(code: u64, msg: String, details: Option<String>) -> Self {
        Error { code, msg, details }
    }
}

/// CommonCNIErrorCodes
#[derive(Debug, Copy, Clone)]
pub enum ErrorCode {
    /// Incompatible CNI version
    IncompatibleCniVersion = 1,
    /// Unsupported field in network configuration. The error message must contain the key and value of the unsupported field.
    UnsupportedConfigField = 2,
    /// Container unknown or does not exist. This error implies the runtime does not need to perform any container network cleanup (for example, calling the DEL action on the container).
    ContainerUnknown = 3,
    /// Invalid necessary environment variables, like CNI_COMMAND, CNI_CONTAINERID, etc. The error message must contain the names of invalid variables.
    InvalidEnvironmentVars = 4,
    /// I/O failure. For example, failed to read network config bytes from stdin.
    IoFailure = 5,
    /// Failed to decode content. For example, failed to unmarshal network config from bytes or failed to decode version info from string.
    FailedToDecodeContent = 6,
    /// Invalid network config. If some validations on network configs do not pass, this error will be raised.
    InvalidNetworkConfig = 7,
    /// Try again later. If the plugin detects some transient condition that should clear up, it can use this code to notify the runtime it should re-try the operation later.
    TryAgainLater = 11,
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_parse_config_long() {
        // Example from CNI spec
        let data = r#"
        {
            "cniVersion": "1.0.0",
            "name": "dbnet",
            "plugins": [
              {
                "type": "bridge",
                "bridge": "cni0",
                "keyA": ["some more", "plugin specific", "configuration"],    
                "ipam": {
                  "type": "host-local",
                  "subnet": "10.1.0.0/16",
                  "gateway": "10.1.0.1",
                  "routes": [
                      {"dst": "0.0.0.0/0"}
                  ]
                },
                "dns": {
                  "nameservers": [ "10.1.0.1" ]
                }
              },
              {
                "type": "tuning",
                "capabilities": {
                  "mac": true
                },
                "sysctl": {
                  "net.core.somaxconn": "500"
                }
              },
              {
                  "type": "portmap",
                  "capabilities": {"portMappings": true}
              }
            ]
          }"#;

        let c: Config = serde_json::from_str(data).unwrap();

        assert_eq!(c.plugins.len(), 3);
    }

    #[test]
    fn test_parse_add_config() {
        let data = r#"{
            "cniVersion": "1.0.0",
            "name": "dbnet",
            "type": "bridge",
            "bridge": "cni0",
            "keyA": ["some more", "plugin specific", "configuration"],
            "ipam": {
                "type": "host-local",
                "subnet": "10.1.0.0/16",
                "gateway": "10.1.0.1",
                "routes": [
                    {"dst": "0.0.0.0/0"}
                ]
            },
            "dns": {
                "nameservers": [ "10.1.0.1" ]
            }
        }"#;

        let a: NetworkConfig = serde_json::from_str(data).unwrap();

        if let Some(ipam) = a.plugin.ipam {
            assert_eq!(ipam.type_, "host-local");
        }
    }

    #[test]
    fn test_parse_error() {
        let data = r#"{
            "code": 7,
            "msg": "Invalid Configuration",
            "details": "Network 192.168.0.0/31 too small to allocate from."
        }"#;

        let e: Error = serde_json::from_str(data).unwrap();
        assert_eq!(
            e.details,
            Some("Network 192.168.0.0/31 too small to allocate from.".to_string())
        )
    }
}
