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

use aya::{
    include_bytes_aligned,
    maps::{MapRefMut, SockHash},
    programs::{SkMsg, SockOps},
    Bpf,
};
use aya_log::BpfLogger;
use patu_common::SockKey;

fn bpf() -> Result<(), anyhow::Error> {
    // This will include your eBPF object file as raw bytes at compile-time and load it at
    // runtime. This approach is recommended for most real-world use cases. If you would
    // like to specify the eBPF program at runtime rather than at compile-time, you can
    // reach for `Bpf::load_file` instead.
    #[cfg(debug_assertions)]
    let mut bpf = Bpf::load(include_bytes_aligned!(
        "../../target/bpfel-unknown-none/debug/patu"
    ))?;
    #[cfg(not(debug_assertions))]
    let mut bpf = Bpf::load(include_bytes_aligned!(
        "../../target/bpfel-unknown-none/release/patu"
    ))?;

    let sock_ops: &mut SockOps = bpf.program_mut("sockops").unwrap().try_into()?;
    sock_ops.load()?;

    let pod1_cgroup = std::fs::File::open("/sys/fs/cgroup/system.slice/runc-pod1.scope")
        .map_err(Error::InvalidCgroup)?;
    sock_ops.attach(pod1_cgroup)?;
    let pod2_cgroup = std::fs::File::open("/sys/fs/cgroup/system.slice/runc-pod2.scope")
        .map_err(Error::InvalidCgroup)?;
    sock_ops.attach(pod2_cgroup)?;
    let pod3_cgroup = std::fs::File::open("/sys/fs/cgroup/system.slice/runc-pod3.scope")
        .map_err(Error::InvalidCgroup)?;
    sock_ops.attach(pod3_cgroup)?;

    let sock_map = SockHash::<MapRefMut, SockKey>::try_from(bpf.map_mut("TCP_CONNS")?)?;

    let redir: &mut SkMsg = bpf.program_mut("patu").unwrap().try_into()?;
    redir.load()?;
    redir.attach(&sock_map)?;

    info!("Waiting for Ctrl-C...");
    signal::ctrl_c().await?;
    info!("Exiting...");
}
