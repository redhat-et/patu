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

static inline void logSkskbMetadata(struct __sk_buff *skb) {
  print_info("skmsg src-ip : >>%X<<  src-port: %d", bpf_htonl(skb->local_ip4),
             bpf_htons(skb->local_port));
  print_info("skmsg dest-ip: >>%X<< dest-port: %d", bpf_htonl(skb->remote_ip4),
             bpf_htons(skb->remote_port));
}

static inline void extract_socket_key_v4(struct __sk_buff *skb,
                                         struct socket_key *sockkey) {

  sockkey->src_ip = skb->remote_ip4;
  sockkey->dst_ip = skb->local_ip4;
  sockkey->src_port = skb->remote_port >> 16;
  sockkey->dst_port = bpf_htonl(skb->local_port);
}

__section("sk_skb") int patu_skskb(struct __sk_buff *skb) {
  logSkskbMetadata(skb);

  struct socket_key sockkey = {};
  extract_socket_key_v4(skb, &sockkey);
  long result =
      sk_redirect_hash(skb, &sockops_redir_map, &sockkey, BPF_F_INGRESS);
  if (result) {
    print_info(" sk_skb, packets redirected from source port %d "
               "to destination port %d",
               skb->local_port, bpf_htonl(skb->remote_port));
  }
  return SK_PASS;
}

char ____license[] __section("license") = "GPL";
int _version __section("version") = 1;
