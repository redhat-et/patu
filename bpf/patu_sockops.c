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

static inline void logSockopsMetadata(struct bpf_sock_ops *ctx) {
  print_info("sockops src-ip : >>%X<<  src-port: %d", bpf_htonl(ctx->local_ip4),
             bpf_htons(ctx->local_port));
  print_info("sockops dest-ip: >>%X<< dest-port: %d",
             bpf_htonl(ctx->remote_ip4), ctx->remote_port >> 16);
}

static inline void extract_socket_key_v4(struct bpf_sock_ops *sockops,
                                         struct socket_key *sockkey) {

  sockkey->src_ip = sockops->local_ip4;
  sockkey->src_port = bpf_htons(sockops->local_port);
  sockkey->dst_ip = sockops->remote_ip4;
  sockkey->dst_port = sockops->remote_port >> 16;
}

static inline int process_sockops_ipv4(struct bpf_sock_ops *skops) {

  struct socket_key sockkey = {};
  extract_socket_key_v4(skops, &sockkey);
  int ret = sock_hash_update(skops, &sockops_redir_map, &sockkey, BPF_NOEXIST);
  if (ret != 0) {
    print_info("ERROR: failed to updated sock hash map, ret: %d\n", ret);
  } else {
    print_info(
        "Socket key is added successfully. ipv4 op = %d, port %d --> %d\n",
        skops->op, skops->local_port, bpf_htonl(skops->remote_port));
  }

  return ret;
}

__section("sockops") int patu_sockops(struct bpf_sock_ops *skops) {
  logSockopsMetadata(skops);

  __u32 family, operator;
  family = skops->family;
  operator= skops->op;

  switch (operator) {
  case BPF_SOCK_OPS_PASSIVE_ESTABLISHED_CB:
  case BPF_SOCK_OPS_ACTIVE_ESTABLISHED_CB:
    if (family == 2) { // AFI_NET,refer socket.h
      if (process_sockops_ipv4(skops))
        return 1;
      else
        return 0;
    }
    break;
  default:
    break;
  }
  return 0;
}

char ____license[] __section("license") = "GPL";
int _version __section("version") = 1;
