/*
Copyright © 2022 Authors of Patu

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#include <linux/bpf.h>

#include "include/helpers/helpers.h"
#include "include/helpers/maps.h"

static inline void extract_socket_key_v4(struct bpf_sock_ops *sockops,
                                         struct socket_key *sockkey) {

  sockkey->src_ip = sockops->local_ip4;
  sockkey->src_port = bpf_htonl(sockops->local_port) >> 16;
  sockkey->dst_ip = sockops->remote_ip4;
  sockkey->dst_port = sockops->remote_port >> 16;
}

static inline int is_ipv4_endpoint(__u32 ip) {
  /* Check for static pod network 10.200.0.0/16*/
  int netip = bpf_htonl(0x0ac80000);

  return ((ip & bpf_htonl(0xffff0000)) == (netip & bpf_htonl(0xffff0000)));
}

static inline int process_sockops_ipv4(struct bpf_sock_ops *skops) {
  if (is_ipv4_endpoint(skops->remote_ip4)) {
    struct socket_key sockkey = {};
    extract_socket_key_v4(skops, &sockkey);
    int ret =
        sock_hash_update(skops, &sockops_redir_map, &sockkey, BPF_NOEXIST);
    if (ret != 0) {
      print_info("[sockops] ERROR: failed to updated sock hash map, ret: %d\n",
                 ret);
    }
    return ret;
  }

  return 0;
}

__section("sockops") int patu_sockops(struct bpf_sock_ops *skops) {
  __u32 family, operator;
  family = skops->family;
  operator= skops->op;

  switch (operator) {
  case BPF_SOCK_OPS_PASSIVE_ESTABLISHED_CB:
  case BPF_SOCK_OPS_ACTIVE_ESTABLISHED_CB:
    if (family == 2) { // AFI_NET,refer socket.h
      process_sockops_ipv4(skops);
      break;
    }
  default:
    break;
  }
  return 0;
}

char ____license[] __section("license") = "GPL";
int _version __section("version") = 1;
