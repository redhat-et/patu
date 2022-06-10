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

use std::{cell::RefCell, fs::File, net::Ipv4Addr, os::unix::io::AsRawFd};

use anyhow::{anyhow, bail};
use netlink_packet_route::{
    address,
    constants::*,
    link::nlas::{Info, InfoData, InfoKind, Nla, VethInfo},
    route, AddressMessage, LinkMessage, NetlinkHeader, NetlinkMessage, NetlinkPayload,
    RouteMessage, RtnlMessage,
};
use netlink_sys::{constants::NETLINK_ROUTE, Socket, SocketAddr};
use nix::{
    fcntl::{self, OFlag},
    sched::{setns, CloneFlags},
    sys::stat::Mode,
};
use rand::RngCore;

#[derive(Default, Debug, Clone)]
pub struct Interface {
    pub ifindex: u32,
    pub name: String,
    pub mac: Option<String>,
}

pub struct NetlinkManager {
    sock: RefCell<Socket>,
}

impl NetlinkManager {
    pub(crate) fn new() -> Self {
        NetlinkManager {
            sock: RefCell::new(init_sock()),
        }
    }

    pub(crate) fn new_in_namespace(ns: String) -> Result<Self, anyhow::Error> {
        Ok(NetlinkManager {
            sock: RefCell::new(init_namespace_sock(ns)?),
        })
    }

    fn send_message(&self, mut msg: NetlinkMessage<RtnlMessage>) -> Result<(), anyhow::Error> {
        msg.finalize();
        let mut buf = vec![0; msg.header.length as usize];
        msg.serialize(&mut buf[..]);

        let socket = self.sock.borrow_mut();
        socket
            .send(&buf, 0)
            .expect("failed to send netlink message");

        let mut receive_buffer = vec![0; 4096];
        let n = socket.recv(&mut &mut receive_buffer[..], 0)?;
        let bytes = &receive_buffer[..n];
        let rx_packet = <NetlinkMessage<RtnlMessage>>::deserialize(bytes).unwrap();
        match rx_packet.payload {
            NetlinkPayload::Ack(_) => Ok(()),
            NetlinkPayload::Error(e) => {
                if e.code == -17 {
                    Ok(())
                } else {
                    Err(anyhow!(e))
                }
            }
            m => Err(anyhow!("unexpected netlink message {:?}", m)),
        }
    }

    pub(crate) fn create_gateway(&self) -> Result<Option<Interface>, anyhow::Error> {
        let mut dummy = LinkMessage::default();
        dummy.nlas.push(Nla::IfName("patu0".to_string()));
        dummy.header.flags |= IFF_UP;
        dummy.header.change_mask |= IFF_UP;
        dummy
            .nlas
            .push(Nla::Info(vec![Info::Kind(InfoKind::Dummy)]));

        let msg = NetlinkMessage {
            header: NetlinkHeader {
                flags: NLM_F_REQUEST | NLM_F_CREATE | NLM_F_EXCL | NLM_F_ACK,
                ..Default::default()
            },
            payload: NetlinkPayload::from(RtnlMessage::NewLink(dummy)),
        };

        self.send_message(msg)?;

        let (ifindex, mac) = self.get_link_info("patu0".to_string())?;
        Ok(Some(Interface {
            ifindex,
            name: "patu0".to_string(),
            mac: Some(mac),
        }))
    }

    pub(crate) fn create_veth_pair(
        &self,
        peer_name: String,
        netns: String,
        mtu: u32,
    ) -> Result<(Interface, Interface), anyhow::Error> {
        let f = File::open(&netns)?; // Peer is the host-side of the veth pair
        let mut peer = LinkMessage::default();
        let name = veth_name();
        peer.nlas.push(Nla::Mtu(mtu));
        peer.nlas.push(Nla::IfName(name.clone()));
        let link_info_data = InfoData::Veth(VethInfo::Peer(peer));
        let link_info_nlas = vec![Info::Kind(InfoKind::Veth), Info::Data(link_info_data)];

        // Veth is the container-side of the veth pair
        let mut veth = LinkMessage::default();
        veth.nlas.push(Nla::Mtu(mtu));
        veth.nlas.push(Nla::IfName(peer_name.clone()));
        veth.nlas.push(Nla::NetNsFd(f.as_raw_fd()));
        veth.nlas.push(Nla::Info(link_info_nlas));

        let msg = NetlinkMessage {
            header: NetlinkHeader {
                flags: NLM_F_REQUEST | NLM_F_CREATE | NLM_F_EXCL | NLM_F_ACK,
                ..Default::default()
            },
            payload: NetlinkPayload::from(RtnlMessage::NewLink(veth)),
        };

        self.send_message(msg)?;
        let (ifindex, mac) = self.get_link_info(name.clone())?;
        Ok((
            Interface {
                ifindex,
                name,
                mac: Some(mac),
            },
            Interface {
                name: peer_name,
                ..Default::default()
            },
        ))
    }

    pub(crate) fn set_ip(&self, index: u32, address: Ipv4Addr) -> Result<(), anyhow::Error> {
        let mut addr = AddressMessage::default();
        addr.header.family = AF_INET as u8;
        addr.header.prefix_len = 32;
        addr.header.index = index;
        addr.nlas
            .push(address::Nla::Address(address.octets().to_vec()));
        addr.nlas
            .push(address::Nla::Local(address.octets().to_vec()));
        addr.nlas
            .push(address::Nla::Broadcast(address.octets().to_vec()));

        let msg = NetlinkMessage {
            header: NetlinkHeader {
                flags: NLM_F_REQUEST | NLM_F_ACK | NLM_F_EXCL | NLM_F_CREATE,
                ..Default::default()
            },
            payload: NetlinkPayload::from(RtnlMessage::NewAddress(addr)),
        };

        self.send_message(msg)
    }

    pub(crate) fn set_up(&self, index: u32) -> Result<(), anyhow::Error> {
        let mut addr = LinkMessage::default();
        addr.header.index = index;
        addr.header.flags |= IFF_UP;
        addr.header.change_mask |= IFF_UP;
        let msg = NetlinkMessage {
            header: NetlinkHeader {
                flags: NLM_F_REQUEST | NLM_F_ACK | NLM_F_EXCL | NLM_F_CREATE,
                ..Default::default()
            },
            payload: NetlinkPayload::from(RtnlMessage::SetLink(addr)),
        };

        self.send_message(msg)
    }

    pub(crate) fn get_link_info(&self, name: String) -> Result<(u32, String), anyhow::Error> {
        let mut iface = LinkMessage::default();
        iface.nlas.push(Nla::IfName(name));
        iface.nlas.push(Nla::ExtMask(RTEXT_FILTER_VF));

        let mut msg = NetlinkMessage {
            header: NetlinkHeader {
                flags: NLM_F_REQUEST | NLM_F_ACK,
                ..Default::default()
            },
            payload: NetlinkPayload::from(RtnlMessage::GetLink(iface)),
        };

        msg.finalize();
        let mut buf = vec![0; msg.header.length as usize];
        msg.serialize(&mut buf[..]);

        let socket = self.sock.borrow_mut();
        socket
            .send(&buf, 0)
            .expect("failed to send netlink message");

        let mut receive_buffer = vec![0; 4096];
        let mut results = vec![];

        loop {
            let n = socket.recv(&mut &mut receive_buffer[..], 0)?;
            let bytes = &receive_buffer[..n];
            let rx_packet = <NetlinkMessage<RtnlMessage>>::deserialize(bytes).unwrap();
            match rx_packet.payload {
                NetlinkPayload::Ack(_) => break,
                NetlinkPayload::Error(e) => bail!(e),
                NetlinkPayload::InnerMessage(RtnlMessage::NewLink(entry)) => results.push(entry),
                m => bail!("unexpected netlink message {:?}", m),
            }
        }

        if results.len() > 1 {
            bail!("more than one interface with this name")
        }

        let mut mac_address = [0u8; 6];
        for nla in &results[0].nlas {
            match nla {
                Nla::Address(addr) => {
                    mac_address.copy_from_slice(&addr[..6]);
                    break;
                }
                _ => continue,
            }
        }

        let result = format!(
            "{:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
            mac_address[0],
            mac_address[1],
            mac_address[2],
            mac_address[3],
            mac_address[4],
            mac_address[5]
        );
        Ok((results[0].header.index, result))
    }

    pub(crate) fn create_default_route(&self, gw: Ipv4Addr) -> Result<(), anyhow::Error> {
        let mut socket = Socket::new(NETLINK_ROUTE).unwrap();
        socket.bind_auto().unwrap();
        socket.connect(&SocketAddr::new(0, 0)).unwrap();

        let mut route = RouteMessage::default();
        route.header.table = RT_TABLE_MAIN;
        route.header.protocol = RTPROT_STATIC;
        route.header.scope = RT_SCOPE_UNIVERSE;
        route.header.kind = RTN_UNICAST;
        route.header.address_family = AF_INET as u8;
        route.nlas.push(route::Nla::Gateway(gw.octets().to_vec()));

        let msg = NetlinkMessage {
            header: NetlinkHeader {
                flags: NLM_F_REQUEST | NLM_F_ACK | NLM_F_EXCL | NLM_F_CREATE,
                ..Default::default()
            },
            payload: NetlinkPayload::from(RtnlMessage::NewRoute(route)),
        };

        self.send_message(msg)
    }

    pub(crate) fn create_dev_route(
        &self,
        ifindex: u32,
        dst: Ipv4Addr,
    ) -> Result<(), anyhow::Error> {
        let mut route = RouteMessage::default();
        route.header.table = RT_TABLE_MAIN;
        route.header.protocol = RTPROT_STATIC;
        route.header.scope = RT_SCOPE_LINK;
        route.header.kind = RTN_UNICAST;
        route.header.address_family = AF_INET as u8;
        route.header.destination_prefix_length = 32;
        route.nlas.push(route::Nla::Oif(ifindex));
        route
            .nlas
            .push(route::Nla::Destination(dst.octets().to_vec()));

        let msg = NetlinkMessage {
            header: NetlinkHeader {
                flags: NLM_F_REQUEST | NLM_F_ACK | NLM_F_EXCL | NLM_F_CREATE,
                ..Default::default()
            },
            payload: NetlinkPayload::from(RtnlMessage::NewRoute(route)),
        };

        self.send_message(msg)
    }

    pub(crate) fn delete_link(&self, ifindex: u32) -> Result<(), anyhow::Error> {
        let mut del = LinkMessage::default();
        del.header.index = ifindex;
        let msg = NetlinkMessage {
            header: NetlinkHeader {
                flags: NLM_F_REQUEST | NLM_F_CREATE | NLM_F_EXCL | NLM_F_ACK,
                ..Default::default()
            },
            payload: NetlinkPayload::from(RtnlMessage::DelLink(del)),
        };
        self.send_message(msg)
    }
}

fn veth_name() -> String {
    let mut entropy = [0u8; 4];
    rand::thread_rng().fill_bytes(&mut entropy);
    format!(
        "veth{:02x}{:02x}{:02x}{:02x}",
        entropy[0], entropy[1], entropy[2], entropy[3],
    )
}

fn init_sock() -> Socket {
    let mut socket = Socket::new(NETLINK_ROUTE).unwrap();
    socket.bind_auto().unwrap();
    socket.connect(&SocketAddr::new(0, 0)).unwrap();
    socket
}

fn init_namespace_sock(namespace: String) -> Result<Socket, anyhow::Error> {
    let current_netns = current_netns()?;
    change_netns_fd(namespace)?;
    let mut socket = Socket::new(NETLINK_ROUTE).unwrap();
    socket.bind_auto().unwrap();
    socket.connect(&SocketAddr::new(0, 0)).unwrap();
    change_netns_id(current_netns)?;
    Ok(socket)
}

pub fn current_netns() -> Result<i32, anyhow::Error> {
    // FD is opened with CLOEXEC so it will be closed once we exit
    // We need to keep this alive so we can get back home
    fcntl::open(
        "/proc/self/ns/net",
        OFlag::O_CLOEXEC | OFlag::O_RDONLY,
        Mode::empty(),
    )
    .map_err(|e| anyhow!(e))
}

fn change_netns_fd(path: String) -> Result<(), anyhow::Error> {
    let f = File::open(path)?;
    setns(f.as_raw_fd(), CloneFlags::CLONE_NEWNET).map_err(|e| anyhow!(e))
}

fn change_netns_id(id: i32) -> Result<(), anyhow::Error> {
    setns(id, CloneFlags::CLONE_NEWNET).map_err(|e| anyhow!(e))
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_veth_name() {
        let name = veth_name();
        assert_eq!(12, name.len());
    }
}
